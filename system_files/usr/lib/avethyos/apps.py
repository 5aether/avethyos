"""App stores, command-line tools, and standard Distrobox application exports."""
import argparse
from pathlib import Path
import re
import subprocess

from common import run, user_only


BREW = '/usr/libexec/avethyos-homebrew/bin/brew'
BOX_GUI = 'io.github.dvlv.boxbuddyrs'


def box_name(value):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*', value):
        raise argparse.ArgumentTypeError('Use letters, numbers, dots, hyphens, or underscores.')
    return value


def fedora_image():
    text = Path('/usr/lib/os-release').read_text()
    match = re.search(r'^VERSION_ID="?(\d+)"?$', text, re.M)
    if not match:
        raise ValueError('Cannot determine the Fedora release. Specify --image when creating a box.')
    return 'registry.fedoraproject.org/fedora-toolbox:' + match[1]


def user_flathub():
    # The image supplies system Flathub; new users may have no user remote yet.
    # Keep existing user remotes and their filters rather than resetting them.
    remotes = subprocess.run(['flatpak', 'remotes', '--user', '--columns=name'],
                             check=True, capture_output=True, text=True)
    if 'flathub' not in remotes.stdout.splitlines():
        run(['flatpak', 'remote-add', '--user', '--if-not-exists', '--from', 'flathub',
             '/usr/share/flatpak/remotes.d/flathub.flatpakrepo'])


def register(commands):
    apps = commands.add_parser('apps', help='Install desktop apps from Flathub')
    actions = apps.add_subparsers(dest='operation', required=True)
    actions.add_parser('store', help='Open the graphical app store')
    actions.add_parser('list', help='List installed applications')
    for action in ('search', 'install', 'remove', 'permissions'):
        operation = actions.add_parser(action, help=action.capitalize() + ' a Flatpak app')
        operation.add_argument('app')
        if action in ('install', 'remove', 'permissions'):
            operation.add_argument('--system', action='store_true', help='Use the installation shared by all users')
    tools = commands.add_parser('tools', help='Install command-line tools with Homebrew')
    tools.add_argument('operation', choices=('search', 'install', 'remove', 'list', 'update'))
    tools.add_argument('packages', nargs='*')
    box = commands.add_parser('box', help='Create Linux containers and add their apps to the launcher')
    actions = box.add_subparsers(dest='operation', required=True)
    actions.add_parser('gui', help='Open BoxBuddy, the graphical container manager')
    actions.add_parser('list', help='List your containers')
    create = actions.add_parser('create', help='Create a Fedora container, or select another Linux image')
    create.add_argument('name', type=box_name)
    create.add_argument('--image', help='Container image; default is the matching Fedora toolbox')
    create.add_argument('--nvidia', action='store_true', help='Share the host NVIDIA driver')
    for action in ('enter', 'remove', 'upgrade'):
        operation = actions.add_parser(action)
        operation.add_argument('name', type=box_name)
    for action in ('export', 'unexport'):
        operation = actions.add_parser(action, help='Show or hide a container app in the shell launcher')
        operation.add_argument('name', type=box_name)
        operation.add_argument('app', help='App name or full path to its .desktop file inside the container')


def handle(options):
    user_only()
    operation = options.operation
    if options.command == 'apps':
        if operation == 'store':
            run(['flatpak', 'run', 'io.github.kolunmi.Bazaar'])
        elif operation == 'list':
            run(['flatpak', 'list', '--app'])
        elif operation == 'search':
            run(['flatpak', 'search', options.app])
        elif operation == 'permissions':
            run(['flatpak', 'info', *(['--system'] if options.system else []),
                 '--show-permissions', options.app])
        else:
            action = 'uninstall' if operation == 'remove' else 'install'
            if operation == 'install' and not options.system:
                user_flathub()
            run(['flatpak', action, '--system' if options.system else '--user',
                 *(['flathub'] if action == 'install' else []), options.app], admin=options.system)
    elif options.command == 'tools':
        if operation in ('search', 'install', 'remove') and not options.packages:
            raise ValueError('Add at least one tool name.')
        operation = 'uninstall' if operation == 'remove' else operation
        if operation == 'update':
            run([BREW, 'update'])
            run([BREW, 'upgrade', *options.packages])
        else:
            run([BREW, operation, *options.packages])
    elif operation == 'gui':
        run(['flatpak', 'run', BOX_GUI])
    elif operation == 'create':
        run(['distrobox', 'create', '--name', options.name, '--image', options.image or fedora_image(),
             *(['--nvidia'] if options.nvidia else [])])
    elif operation in ('export', 'unexport'):
        run(['distrobox', 'enter', '--name', options.name, '--', 'distrobox-export',
             '--app', options.app, *(['--delete'] if operation == 'unexport' else [])])
    elif operation == 'enter':
        run(['distrobox', 'enter', '--name', options.name])
    elif operation == 'list':
        run(['distrobox', 'list'])
    else:
        run(['distrobox', 'rm' if operation == 'remove' else 'upgrade', options.name])
