"""Small command groups for the immutable OS and its persistent preferences."""
import argparse
import configparser
import subprocess
import sys

import apps
import desktop
import kernel
import system
from common import run, user_only


def parser():
    root = argparse.ArgumentParser(description='AvethyOS apps, settings, gaming, and system maintenance.')
    commands = root.add_subparsers(dest='command')
    for module in (kernel, desktop, apps, system):
        module.register(commands)
    gaming = commands.add_parser('gaming', help='Test gaming helpers or run a game with them')
    actions = gaming.add_subparsers(dest='operation', required=True)
    actions.add_parser('test', help='Check GameMode and report installed gaming packages')
    launch = actions.add_parser('run', help='Run a command with GameMode and optionally MangoHud/Gamescope')
    launch.add_argument('--hud', action='store_true')
    launch.add_argument('--gamescope', action='store_true')
    launch.add_argument('program', nargs=argparse.REMAINDER, help='Use -- before the game command')
    return root


def gaming(options):
    user_only()
    if options.operation == 'test':
        run(['rpm', '-q', 'gamescope', 'gamemode', 'mangohud'])
        run(['gamemoded', '-t'])
        return
    arguments = options.program[1:] if options.program[:1] == ['--'] else options.program
    if not arguments:
        raise ValueError('Add a game command after --.')
    if options.gamescope:
        arguments = ['gamescope', '-f', *(['--mangoapp'] if options.hud else []), '--', *arguments]
    elif options.hud:
        arguments = ['mangohud', *arguments]
    arguments = ['gamemoderun', *arguments]
    run(arguments)


def main(argv=None):
    root = parser()
    options = root.parse_args(argv)
    if options.command is None:
        root.print_help()
        return 0
    handlers = {'kernel': kernel.handle, 'fnmode': kernel.handle,
                'config': desktop.handle, 'wallpaper': desktop.handle, 'shell': desktop.handle,
                'apps': apps.handle, 'tools': apps.handle, 'box': apps.handle, 'gaming': gaming}
    try:
        handlers.get(options.command, system.handle)(options)
        return 0
    except (OSError, ValueError, RuntimeError, configparser.Error, subprocess.CalledProcessError) as error:
        print(f'avethyos: {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
