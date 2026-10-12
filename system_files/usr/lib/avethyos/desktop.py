"""Editable desktop preferences and the shell's existing IPC interface."""
import configparser
import io
import os
from pathlib import Path
import shlex
import tempfile

from common import DESKTOP, run, user_only, xdg


# Every setting the shell reads, with its accepted type or range.
SETTINGS = {
    'appearance.icon-pack': str,
    'wallpaper.path': str,
    'wallpaper.folder': str,
    'wallpaper.fillMode': ('cover', 'fit', 'stretch'),
    'wallpaper.enabled': bool,
    'notifications.maxVisibleToasts': (1, 10),
    'notifications.toastDurationMs': (1500, 60000),
    'notifications.doNotDisturb': bool,
    'display.nightLightEnabled': bool,
    'display.nightLightTemperature': (1000, 6500),
}
USER_FILES = {'shortcuts': 'shortcuts.lua', 'monitors': 'monitors.lua',
              'input': 'input.lua', 'appearance': 'appearance.lua',
              'rules': 'window-rules.lua', 'custom': 'custom.lua',
              'lock': 'hyprlock.conf', 'idle': 'hypridle.conf'}
PANELS = {'apps': 'applauncher', 'settings': 'controlcenter',
          'notifications': 'clock', 'clipboard': 'clipboard', 'media': 'mediaplayer'}


def settings_path():
    return xdg('XDG_STATE_HOME', '.local/state') / 'avethyos/quickshell/config.ini'


def read_settings(path=None):
    path = settings_path() if path is None else path
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str
    config.read(path if path.exists() else DESKTOP / 'quickshell/config.ini')
    return config


def setting_value(key, value):
    if key not in SETTINGS:
        raise ValueError('Unknown setting. Run avethyos config list to see the available names.')
    if any(c in value for c in '\n\r\x00'):
        raise ValueError('Settings must fit on one line.')
    kind = SETTINGS[key]
    if kind is bool:
        values = {'on': 'true', 'yes': 'true', '1': 'true', 'true': 'true',
                  'off': 'false', 'no': 'false', '0': 'false', 'false': 'false'}
        if value.lower() not in values:
            raise ValueError('Use on or off for this setting.')
        return values[value.lower()]
    if isinstance(kind, tuple):
        if isinstance(kind[0], int):
            number = int(value)
            if not kind[0] <= number <= kind[1]:
                raise ValueError(f'Use a number from {kind[0]} to {kind[1]}.')
            return str(number)
        if value not in kind:
            raise ValueError('Choose: ' + ', '.join(kind))
    return value


def set_setting(key, value, path=None):
    value = setting_value(key, value)
    path = settings_path() if path is None else path
    config = read_settings(path)
    section, name = key.split('.', 1)
    if not config.has_section(section):
        config.add_section(section)
    config[section][name] = value
    content = io.StringIO()
    config.write(content)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.avethyos-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content.getvalue())
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def edit(name):
    user_only()
    run(['python3', '/usr/libexec/avethyos-user-config'])
    config_home = xdg('XDG_CONFIG_HOME', '.config')
    if name == 'shell':
        path = settings_path()
    elif name in USER_FILES:
        path = config_home / 'hypr' / USER_FILES[name]
    else:
        path = config_home / ('MangoHud/MangoHud.conf' if name == 'mangohud' else 'gamemode.ini')
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text('# Your gaming preferences; this file survives OS updates.\n')
    editor = shlex.split(os.environ.get('VISUAL') or os.environ.get('EDITOR') or 'nano')
    run([*editor, str(path)])


def register(commands):
    config = commands.add_parser('config', help='List, change, or edit desktop preferences')
    actions = config.add_subparsers(dest='operation', required=True)
    actions.add_parser('list', help='Show every shell setting and its value')
    get = actions.add_parser('get', help='Read one shell setting')
    get.add_argument('key', choices=SETTINGS)
    change = actions.add_parser('set', help='Change one setting; the shell updates automatically')
    change.add_argument('key', choices=SETTINGS)
    change.add_argument('value')
    editor = actions.add_parser('edit', help='Open a commented preferences file')
    editor.add_argument('file', choices=['shell', *USER_FILES, 'mangohud', 'gamemode'])
    wallpaper = commands.add_parser('wallpaper', help='Choose an image or video wallpaper')
    wallpaper.add_argument('path', type=Path)
    shell = commands.add_parser('shell', help='Restart the shell, reload Hyprland, or toggle a panel')
    shell.add_argument('action', choices=['restart', 'reload', *PANELS])


def handle(options):
    if options.command == 'shell':
        user_only()
        if options.action == 'restart':
            run(['python3', str(DESKTOP / 'quickshell/scripts/restart-shell.py'), '--daemonize'])
        elif options.action == 'reload':
            run(['hyprctl', 'reload'])
        else:
            run(['qs', '-p', str(DESKTOP / 'quickshell'), 'ipc', 'call',
                 PANELS[options.action], 'toggle'])
    elif options.command == 'wallpaper':
        user_only()
        path = options.path.expanduser().resolve(strict=True)
        if not path.is_file():
            raise ValueError('Choose an image or video file.')
        set_setting('wallpaper.path', path.as_uri())
        set_setting('wallpaper.enabled', 'on')
    elif options.operation == 'edit':
        edit(options.file)
    elif options.operation == 'set':
        user_only()
        set_setting(options.key, options.value)
        print('Saved. The running shell reads this change automatically.')
    else:
        config = read_settings()
        for key in SETTINGS if options.operation == 'list' else [options.key]:
            section, name = key.split('.', 1)
            value = config.get(section, name, fallback='(default)')
            print(f'{key} = {value}' if options.operation == 'list' else value)
