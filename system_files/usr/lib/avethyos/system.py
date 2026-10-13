"""Native system maintenance, registry login, and diagnostics."""
import getpass
import os
from pathlib import Path
import re
import shutil
import subprocess

from apps import BREW
from common import DESKTOP, run, user_only


SERVICES = {'bluetooth': 'bluetooth.service', 'network': 'NetworkManager.service',
            'ssh': 'sshd.service', 'auto-updates': 'bootc-fetch-apply-updates.timer',
            'rpc': 'avethyos-discord-rpc.service'}


def register(commands):
    commands.add_parser('status', help='Show the installed and staged OS images')
    update = commands.add_parser('update', help='Download the next OS version for your next boot')
    update.add_argument('--all', action='store_true', help='Also update Flatpaks, Homebrew tools and containers')
    commands.add_parser('rollback', help='Stage the previous OS version for your next boot')
    image = commands.add_parser('image', help='Switch images or sign in to a private image registry')
    actions = image.add_subparsers(dest='operation', required=True)
    actions.add_parser('status', help='Show your OS images')
    switch = actions.add_parser('switch', help='Stage another bootc image; reboot later to use it')
    switch.add_argument('reference', help='For example ghcr.io/your-name/avethyos:latest')
    login = actions.add_parser('login', help='Save credentials for bootc and automatic updates')
    login.add_argument('username')
    login.add_argument('--registry', default='ghcr.io')
    logout = actions.add_parser('logout', help='Remove saved credentials from a registry')
    logout.add_argument('--registry', default='ghcr.io')
    system = commands.add_parser('system', help='Change the computer name, time zone, or language')
    system.add_argument('setting', choices=('hostname', 'timezone', 'locale'))
    system.add_argument('value')
    service = commands.add_parser('service', help='Inspect or enable an installed system service')
    service.add_argument('name', choices=SERVICES)
    service.add_argument('action', choices=('status', 'on', 'off'))
    commands.add_parser('doctor', help='Check tools, desktop integration, and container setup')
    commands.add_parser('readme', help='Read the guide installed with this image')
    recipes = commands.add_parser('recipes', help='List or run short maintenance recipes')
    recipes.add_argument('recipe', nargs='?')


def registry(value):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.-]*(?::[0-9]+)?', value):
        raise ValueError('Use a registry hostname such as ghcr.io, without https:// or a path.')
    return value


def image_reference(value):
    if (not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._:/@-]*', value)
            or '/' not in value or '://' in value):
        raise ValueError('Use a full image name, such as ghcr.io/your-name/avethyos:latest.')
    return value


def doctor():
    failed = []
    for tool in ('python3', 'bootc', 'Hyprland', 'qs', 'flatpak', 'distrobox', 'podman',
                 'newuidmap', 'newgidmap', 'pasta', 'fuse-overlayfs',
                 'gamescope', 'gamemoded', 'gamemoderun', 'mangohud', 'fastfetch',
                 'kitty', 'which', 'lspci', 'nano', 'just'):
        found = shutil.which(tool)
        print(f'{tool}: {found or "missing"}')
        if not found:
            failed.append(tool)
    for name in ('hypr/hyprland.lua', 'quickshell/shell.qml'):
        found = (DESKTOP / name).is_file()
        print(f'{name}: {"present" if found else "missing"}')
        if not found:
            failed.append(name)
    if os.geteuid() != 0:
        user = getpass.getuser()
        for name in ('subuid', 'subgid'):
            path = Path('/etc') / name
            entries = path.read_text().splitlines() if path.exists() else []
            assigned = any(entry.split(':')[0] in (user, str(os.getuid())) for entry in entries)
            print(f'{name}: {"assigned" if assigned else "missing; sign out and back in after an OS update"}')
            if not assigned:
                failed.append(name)
        result = subprocess.run(['podman', 'info'], stdout=subprocess.DEVNULL, check=False)
        print(f'Rootless containers: {"ready" if result.returncode == 0 else "not ready"}')
        if result.returncode:
            failed.append('rootless containers')
    if failed:
        raise ValueError('Checks failed: ' + ', '.join(failed))


def handle(options):
    command = options.command
    if command == 'status' or (command == 'image' and options.operation == 'status'):
        run(['bootc', 'status'])
    elif command == 'update':
        if options.all:
            user_only()
        run(['bootc', 'upgrade'], admin=True)
        if options.all:
            run(['flatpak', 'update', '--user'])
            run(['flatpak', 'update', '--system'], admin=True)
            run([BREW, 'update'])
            run([BREW, 'upgrade'])
            run(['distrobox', 'upgrade', '--all'])
        print('Update staged. Reboot when you are ready to use it.')
    elif command == 'rollback':
        run(['bootc', 'rollback'], admin=True)
        print('Previous OS staged. Reboot when you are ready to use it.')
    elif command == 'image':
        if options.operation == 'switch':
            run(['bootc', 'switch', image_reference(options.reference)], admin=True)
            print('Image staged. Reboot when you are ready to use it.')
        else:
            hostname = registry(options.registry)
            run(['install', '-d', '-m', '0700', '/etc/ostree'], admin=True)
            arguments = ['podman', options.operation, '--authfile', '/etc/ostree/auth.json']
            if options.operation == 'login':
                token = getpass.getpass('Registry token (for GHCR use a token with read:packages): ')
                run([*arguments, '--username', options.username, '--password-stdin', hostname],
                    admin=True, input=token + '\n', text=True)
                run(['chmod', '0600', '/etc/ostree/auth.json'], admin=True)
                print('Credentials saved for bootc upgrades, including automatic updates.')
            else:
                run([*arguments, hostname], admin=True)
    elif command == 'system':
        tool, setting = {'hostname': ('hostnamectl', 'set-hostname'),
                         'timezone': ('timedatectl', 'set-timezone'),
                         'locale': ('localectl', 'set-locale')}[options.setting]
        value = 'LANG=' + options.value if options.setting == 'locale' else options.value
        run([tool, setting, value], admin=True)
    elif command == 'service':
        user = options.name == 'rpc'
        if user:
            user_only()
        action = {'on': ['enable', '--now'], 'off': ['disable', '--now'], 'status': ['status']}[options.action]
        arguments = ['systemctl', *(['--user'] if user else []), *action, SERVICES[options.name]]
        if options.action == 'status':
            # An installed inactive service returns 3; its status is still useful.
            result = subprocess.run(arguments, check=False)
            if result.returncode not in (0, 3):
                raise ValueError('Could not read the service status.')
        else:
            run(arguments, admin=not user)
    elif command == 'doctor':
        doctor()
    elif command == 'readme':
        path = Path('/usr/share/doc/avethyos/README.md')
        if shutil.which('less'):
            run(['less', str(path)])
        else:
            print(path.read_text())
    elif command == 'recipes':
        run(['just', '--justfile', str(DESKTOP / 'recipes.just'),
             *([options.recipe] if options.recipe else ['--list'])])
