"""Exercise settings, privilege boundaries, and command routing without touching the host."""
import argparse
import contextlib
import io
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import call, patch


MODULES = Path(__file__).resolve().parents[1] / 'system_files/usr/lib/avethyos'
sys.path.insert(0, str(MODULES))
import cli
import apps
import common
import desktop
import system


class CliTests(unittest.TestCase):
    def call(self, arguments):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cli.main(arguments)

    def test_no_arguments_shows_help_without_running_commands(self):
        with patch.object(common.subprocess, 'run') as runner:
            self.assertEqual(self.call([]), 0)
            runner.assert_not_called()

    def test_settings_preserve_other_values_case_and_literal_text(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'settings.ini'
            path.write_text('[wallpaper]\nfillMode = fit\n[notifications]\ndoNotDisturb = false\n')
            desktop.set_setting('wallpaper.path', '/home/me/100% wallpaper.mp4', path)
            desktop.set_setting('notifications.doNotDisturb', 'on', path)
            config = desktop.read_settings(path)
            self.assertEqual(config['wallpaper']['fillMode'], 'fit')
            self.assertEqual(config['wallpaper']['path'], '/home/me/100% wallpaper.mp4')
            self.assertEqual(config['notifications']['doNotDisturb'], 'true')

    def test_invalid_settings_never_change_the_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'settings.ini'
            path.write_text('[wallpaper]\nfillMode = cover\n')
            before = path.read_bytes()
            for key, value in [('wallpaper.path', 'x\n[display]'), ('wallpaper.fillMode', 'wrong'),
                               ('notifications.maxVisibleToasts', '0'),
                               ('display.nightLightTemperature', '9000'),
                               ('display.nightLightEnabled', 'maybe')]:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    desktop.set_setting(key, value, path)
                self.assertEqual(path.read_bytes(), before)

    def test_desktop_settings_cannot_be_written_as_root(self):
        with patch.object(common.os, 'geteuid', return_value=0), patch.object(desktop, 'set_setting') as write:
            self.assertEqual(self.call(['config', 'set', 'wallpaper.enabled', 'off']), 1)
            write.assert_not_called()

    def test_distrobox_export_passes_arguments_without_shell_interpretation(self):
        with patch.object(common.os, 'geteuid', return_value=1000), patch.object(common.subprocess, 'run') as run:
            self.assertEqual(self.call(['box', 'export', 'fedora', '/opt/My App/app.desktop']), 0)
            run.assert_called_once_with(['distrobox', 'enter', '--name', 'fedora', '--',
                                         'distrobox-export', '--app', '/opt/My App/app.desktop'], check=True)

    def test_gaming_run_composes_helpers_and_preserves_game_arguments(self):
        with patch.object(common.os, 'geteuid', return_value=1000), patch.object(common.subprocess, 'run') as run:
            self.assertEqual(self.call(['gaming', 'run', '--hud', '--gamescope', '--', '/opt/My Game/game', '-x']), 0)
            run.assert_called_once_with(['gamemoderun', 'gamescope', '-f', '--mangoapp', '--',
                                         '/opt/My Game/game', '-x'], check=True)

    def test_private_registry_login_keeps_token_out_of_arguments(self):
        with patch.object(system.getpass, 'getpass', return_value='test-secret'), \
                patch.object(system, 'run') as run:
            self.assertEqual(self.call(['image', 'login', 'owner']), 0)
            command = run.call_args_list[1]
            self.assertNotIn('test-secret', command.args[0])
            self.assertIn('/etc/ostree/auth.json', command.args[0])
            self.assertEqual(command.kwargs['input'], 'test-secret\n')
            self.assertTrue(command.kwargs['admin'])

    def test_bad_image_reference_does_not_stage_anything(self):
        with patch.object(system, 'run') as run:
            self.assertEqual(self.call(['image', 'switch', 'https://ghcr.io/me/os']), 1)
            run.assert_not_called()

    def test_user_rpc_service_does_not_request_system_privileges(self):
        with patch.object(common.os, 'geteuid', return_value=1000), patch.object(system, 'run') as run:
            self.assertEqual(self.call(['service', 'rpc', 'on']), 0)
            run.assert_called_once_with(['systemctl', '--user', 'enable', '--now',
                                         'avethyos-discord-rpc.service'], admin=False)

    def test_kernel_settings_still_need_explicit_admin_access(self):
        with patch.object(common.os, 'geteuid', return_value=1000), patch.object(cli.kernel, 'stage') as stage:
            self.assertEqual(self.call(['kernel', 'set', 'quiet']), 1)
            stage.assert_not_called()

    def test_update_only_routes_to_the_backend_and_never_reboots(self):
        # The backend is mocked: this test never executes bootc.
        with patch.object(system, 'run') as run:
            self.assertEqual(self.call(['update']), 0)
            run.assert_called_once_with(['bootc', 'upgrade'], admin=True)

    def test_every_registered_command_and_subcommand_can_show_help(self):
        # Traverse argparse itself, so a new command joins this check automatically.
        paths = []

        def visit(parser, prefix):
            paths.append(prefix)
            for action in parser._actions:
                if isinstance(action, argparse._SubParsersAction):
                    for name, child in action.choices.items():
                        visit(child, [*prefix, name])

        visit(cli.parser(), [])
        with patch.object(common.subprocess, 'run') as runner:
            for path in paths:
                with self.subTest(command=path), self.assertRaises(SystemExit) as result:
                    self.call([*path, '--help'])
                self.assertEqual(result.exception.code, 0)
            runner.assert_not_called()

    def test_app_commands_select_the_requested_installation(self):
        cases = [
            (['apps', 'store'], ['flatpak', 'run', 'io.github.kolunmi.Bazaar'], False),
            (['apps', 'list'], ['flatpak', 'list', '--app'], False),
            (['apps', 'search', 'text editor'], ['flatpak', 'search', 'text editor'], False),
            (['apps', 'install', 'org.example.Editor'],
             ['flatpak', 'install', '--user', 'flathub', 'org.example.Editor'], False),
            (['apps', 'install', '--system', 'org.example.Editor'],
             ['flatpak', 'install', '--system', 'flathub', 'org.example.Editor'], True),
            (['apps', 'remove', 'org.example.Editor'],
             ['flatpak', 'uninstall', '--user', 'org.example.Editor'], False),
            (['apps', 'remove', '--system', 'org.example.Editor'],
             ['flatpak', 'uninstall', '--system', 'org.example.Editor'], True),
            (['apps', 'permissions', 'org.example.Editor'],
             ['flatpak', 'info', '--show-permissions', 'org.example.Editor'], False),
            (['apps', 'permissions', '--system', 'org.example.Editor'],
             ['flatpak', 'info', '--system', '--show-permissions', 'org.example.Editor'], False),
        ]
        with patch.object(common.os, 'geteuid', return_value=1000):
            for arguments, expected, admin in cases:
                with self.subTest(command=arguments), patch.object(common.subprocess, 'run') as run, \
                        patch.object(apps, 'user_flathub'):
                    self.assertEqual(self.call(arguments), 0)
                    run.assert_called_once_with([*(['sudo'] if admin else []), *expected], check=True)
                    if admin:
                        self.assertEqual(run.call_args.args[0][0], 'sudo')

    def test_first_user_app_install_adds_only_a_missing_user_flathub_remote(self):
        for remotes in ('', 'other-remote\n', 'flathub\nother-remote\n'):
            with self.subTest(remotes=remotes), patch.object(common.os, 'geteuid', return_value=1000), \
                    patch.object(common.subprocess, 'run',
                                 return_value=subprocess.CompletedProcess([], 0, stdout=remotes)) as run:
                self.assertEqual(self.call(['apps', 'install', 'org.example.Editor']), 0)
                self.assertEqual(run.call_args_list[0],
                                 call(['flatpak', 'remotes', '--user', '--columns=name'],
                                      check=True, capture_output=True, text=True))
                if 'flathub' not in remotes.splitlines():
                    self.assertEqual(run.call_args_list[1],
                                     call(['flatpak', 'remote-add', '--user', '--if-not-exists', '--from',
                                           'flathub', '/usr/share/flatpak/remotes.d/flathub.flatpakrepo'], check=True))
                    self.assertEqual(run.call_count, 3)
                else:
                    self.assertEqual(run.call_count, 2)
                self.assertEqual(run.call_args_list[-1],
                                 call(['flatpak', 'install', '--user', 'flathub', 'org.example.Editor'], check=True))

    def test_distrobox_commands_use_native_operations_and_gui(self):
        cases = [
            (['box', 'gui'], ['flatpak', 'run', apps.BOX_GUI]),
            (['box', 'list'], ['distrobox', 'list']),
            (['box', 'create', 'work'], ['distrobox', 'create', '--name', 'work', '--image',
                                       'registry.fedoraproject.org/fedora-toolbox:44']),
            (['box', 'create', 'work', '--image', 'docker.io/library/ubuntu:24.04', '--nvidia'],
             ['distrobox', 'create', '--name', 'work', '--image',
              'docker.io/library/ubuntu:24.04', '--nvidia']),
            (['box', 'enter', 'work'], ['distrobox', 'enter', '--name', 'work']),
            (['box', 'remove', 'work'], ['distrobox', 'rm', 'work']),
            (['box', 'upgrade', 'work'], ['distrobox', 'upgrade', 'work']),
            (['box', 'unexport', 'work', '/opt/My App.desktop'],
             ['distrobox', 'enter', '--name', 'work', '--', 'distrobox-export', '--app',
              '/opt/My App.desktop', '--delete']),
        ]
        with patch.object(common.os, 'geteuid', return_value=1000), \
                patch.object(apps, 'fedora_image', return_value='registry.fedoraproject.org/fedora-toolbox:44'):
            for arguments, expected in cases:
                with self.subTest(command=arguments), patch.object(common.subprocess, 'run') as run:
                    self.assertEqual(self.call(arguments), 0)
                    run.assert_called_once_with(expected, check=True)

    def test_homebrew_update_refreshes_index_before_upgrading_selected_tools(self):
        with patch.object(common.os, 'geteuid', return_value=1000), \
                patch.object(common.subprocess, 'run') as run:
            self.assertEqual(self.call(['tools', 'update', 'git', 'ripgrep']), 0)
            self.assertEqual(run.call_args_list, [call([apps.BREW, 'update'], check=True),
                                                 call([apps.BREW, 'upgrade', 'git', 'ripgrep'], check=True)])
        for operation, backend in [('search', 'search'), ('install', 'install'),
                                   ('remove', 'uninstall'), ('list', 'list')]:
            with self.subTest(operation=operation), patch.object(common.os, 'geteuid', return_value=1000), \
                    patch.object(common.subprocess, 'run') as run:
                self.assertEqual(self.call(['tools', operation, 'git']), 0)
                run.assert_called_once_with([apps.BREW, backend, 'git'], check=True)

    def test_updates_switch_and_rollback_only_stage_changes(self):
        # All backends stay mocked, including flatpak/podman, on the real host.
        cases = [(['status'], ['bootc', 'status'], False),
                 (['image', 'status'], ['bootc', 'status'], False),
                 (['rollback'], ['bootc', 'rollback'], True),
                 (['image', 'switch', 'ghcr.io/me/private:latest'],
                  ['bootc', 'switch', 'ghcr.io/me/private:latest'], True)]
        for arguments, expected, admin in cases:
            with self.subTest(command=arguments), patch.object(system, 'run') as run:
                self.assertEqual(self.call(arguments), 0)
                run.assert_called_once_with(expected, **({'admin': True} if admin else {}))
        with patch.object(common.os, 'geteuid', return_value=1000), patch.object(system, 'run') as run:
            self.assertEqual(self.call(['update', '--all']), 0)
            self.assertEqual([entry.args[0] for entry in run.call_args_list],
                             [['bootc', 'upgrade'], ['flatpak', 'update', '--user'],
                              ['flatpak', 'update', '--system'], [apps.BREW, 'update'],
                              [apps.BREW, 'upgrade'], ['distrobox', 'upgrade', '--all']])

    def test_system_settings_and_services_use_native_admin_commands(self):
        for setting, value, expected in [
                ('hostname', 'my-computer', ['hostnamectl', 'set-hostname', 'my-computer']),
                ('timezone', 'Europe/Rome', ['timedatectl', 'set-timezone', 'Europe/Rome']),
                ('locale', 'it_IT.UTF-8', ['localectl', 'set-locale', 'LANG=it_IT.UTF-8'])]:
            with self.subTest(setting=setting), patch.object(system, 'run') as run:
                self.assertEqual(self.call(['system', setting, value]), 0)
                run.assert_called_once_with(expected, admin=True)
        for name, unit in system.SERVICES.items():
            for action, native in [('on', ['enable', '--now']), ('off', ['disable', '--now'])]:
                with self.subTest(service=name, action=action), \
                        patch.object(common.os, 'geteuid', return_value=1000), patch.object(system, 'run') as run:
                    self.assertEqual(self.call(['service', name, action]), 0)
                    run.assert_called_once_with(['systemctl', *(['--user'] if name == 'rpc' else []),
                                                 *native, unit], admin=name != 'rpc')
        for status in (0, 3, 4):
            with self.subTest(status=status), patch.object(system.subprocess, 'run',
                    return_value=subprocess.CompletedProcess([], status)) as run:
                self.assertEqual(self.call(['service', 'ssh', 'status']), 1 if status == 4 else 0)
                run.assert_called_once_with(['systemctl', 'status', 'sshd.service'], check=False)

    def test_shell_panels_and_reload_route_to_existing_ipc_interfaces(self):
        shell_source = (MODULES.parents[3] / 'quickshell/shell.qml').read_text()
        for panel, target in desktop.PANELS.items():
            self.assertIn('target: "' + target + '"', shell_source)
            with self.subTest(panel=panel), patch.object(common.os, 'geteuid', return_value=1000), \
                    patch.object(common.subprocess, 'run') as run:
                self.assertEqual(self.call(['shell', panel]), 0)
                run.assert_called_once_with(['qs', '-p', str(common.DESKTOP / 'quickshell'),
                                             'ipc', 'call', target, 'toggle'], check=True)
        for action, expected in [('reload', ['hyprctl', 'reload']),
                                 ('restart', ['python3', str(common.DESKTOP /
                                  'quickshell/scripts/restart-shell.py'), '--daemonize'])]:
            with self.subTest(action=action), patch.object(common.os, 'geteuid', return_value=1000), \
                    patch.object(common.subprocess, 'run') as run:
                self.assertEqual(self.call(['shell', action]), 0)
                run.assert_called_once_with(expected, check=True)

    def test_all_shell_settings_are_available_and_wallpaper_paths_are_encoded(self):
        defaults = desktop.read_settings(MODULES.parents[3] / 'quickshell/config.ini')
        keys = {section + '.' + key for section in defaults for key in defaults[section]
                if section != defaults.default_section}
        self.assertEqual(keys, set(desktop.SETTINGS))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            wallpaper = root / 'My wallpaper #100%.mp4'
            wallpaper.write_bytes(b'fixture')
            with patch.object(common.os, 'geteuid', return_value=1000), \
                    patch.object(desktop, 'settings_path', return_value=root / 'state/config.ini'):
                self.assertEqual(self.call(['wallpaper', str(wallpaper)]), 0)
                saved = desktop.read_settings()
                self.assertEqual(saved['wallpaper']['path'], wallpaper.as_uri())
                self.assertEqual(saved['wallpaper']['enabled'], 'true')
                self.assertEqual(self.call(['config', 'list']), 0)
                for key in desktop.SETTINGS:
                    with self.subTest(key=key):
                        self.assertEqual(self.call(['config', 'get', key]), 0)

    def test_readme_recipes_and_registry_logout_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            guide = Path(temporary) / 'README.md'
            guide.write_text('Offline guide fixture.\n')
            with patch.object(system, 'Path', return_value=guide), \
                    patch.object(system.shutil, 'which', return_value=None):
                self.assertEqual(self.call(['readme']), 0)
        for recipe, ending in [([], ['--list']), (['doctor'], ['doctor'])]:
            with self.subTest(recipe=recipe), patch.object(system, 'run') as run:
                self.assertEqual(self.call(['recipes', *recipe]), 0)
                run.assert_called_once_with(['just', '--justfile', str(common.DESKTOP / 'recipes.just'), *ending])
        with patch.object(system, 'run') as run:
            self.assertEqual(self.call(['image', 'logout', '--registry', 'ghcr.io']), 0)
            self.assertEqual(run.call_args_list[-1],
                             call(['podman', 'logout', '--authfile', '/etc/ostree/auth.json', 'ghcr.io'], admin=True))

    def test_missing_tool_errors_are_readable_without_a_traceback(self):
        with patch.object(common.os, 'geteuid', return_value=1000), \
                patch.object(common.subprocess, 'run', side_effect=FileNotFoundError('native tool missing')):
            self.assertEqual(self.call(['box', 'gui']), 1)

    def test_preferences_edit_uses_only_user_paths_and_an_argument_list(self):
        with tempfile.TemporaryDirectory() as temporary:
            config_home = Path(temporary) / 'config'
            shell_file = Path(temporary) / 'state/config.ini'
            targets = {'shell': shell_file, **{name: config_home / 'hypr' / filename
                       for name, filename in desktop.USER_FILES.items()},
                       'mangohud': config_home / 'MangoHud/MangoHud.conf',
                       'gamemode': config_home / 'gamemode.ini'}
            with patch.object(common.os, 'geteuid', return_value=1000), \
                    patch.object(desktop, 'xdg', return_value=config_home), \
                    patch.object(desktop, 'settings_path', return_value=shell_file), \
                    patch.dict(desktop.os.environ, {'VISUAL': 'nano --linenumbers'}):
                for name, target in targets.items():
                    with self.subTest(file=name), patch.object(common.subprocess, 'run') as run:
                        self.assertEqual(self.call(['config', 'edit', name]), 0)
                        self.assertEqual(run.call_args_list,
                                         [call(['python3', '/usr/libexec/avethyos-user-config'], check=True),
                                          call(['nano', '--linenumbers', str(target)], check=True)])
                self.assertTrue(targets['mangohud'].is_file())
                self.assertTrue(targets['gamemode'].is_file())

    def test_kernel_commands_and_function_key_modes_keep_native_staging(self):
        # Stage/load are fake; neither bootc nor a real preference file is touched.
        with patch.object(cli.kernel.os, 'geteuid', return_value=0):
            for operation, values in [('set', ['quiet']), ('add', ['console=tty0']),
                                      ('remove', ['quiet']), ('reset', []), ('apply', [])]:
                with self.subTest(operation=operation), patch.object(cli.kernel, 'stage') as stage:
                    self.assertEqual(self.call(['kernel', operation, *values]), 0)
                    stage.assert_called_once_with(operation, values)
            for mode in ('0', '1', '2', '3', '4', 'default'):
                with self.subTest(mode=mode), patch.object(cli.kernel, 'stage') as stage:
                    self.assertEqual(self.call(['fnmode', mode]), 0)
                    stage.assert_called_once_with('remove' if mode == 'default' else 'set',
                                                  ['hid_apple.fnmode' if mode == 'default'
                                                   else 'hid_apple.fnmode=' + mode])
            with patch.object(cli.kernel, 'load', return_value={'arguments': [], 'pending': False}):
                self.assertEqual(self.call(['kernel', 'show']), 0)

    def test_gaming_modes_and_tool_test_preserve_program_arguments(self):
        cases = [([], ['gamemoderun', 'game', '--flag']),
                 (['--hud'], ['gamemoderun', 'mangohud', 'game', '--flag']),
                 (['--gamescope'], ['gamemoderun', 'gamescope', '-f', '--', 'game', '--flag'])]
        with patch.object(common.os, 'geteuid', return_value=1000):
            for flags, expected in cases:
                with self.subTest(flags=flags), patch.object(common.subprocess, 'run') as run:
                    self.assertEqual(self.call(['gaming', 'run', *flags, '--', 'game', '--flag']), 0)
                    run.assert_called_once_with(expected, check=True)
            with patch.object(common.subprocess, 'run') as run:
                self.assertEqual(self.call(['gaming', 'test']), 0)
                self.assertEqual(run.call_args_list, [call(['rpm', '-q', 'gamescope', 'gamemode',
                                                          'mangohud'], check=True),
                                                     call(['gamemoded', '-t'], check=True)])
            with patch.object(common.subprocess, 'run') as run:
                self.assertEqual(self.call(['gaming', 'run']), 1)
                run.assert_not_called()

    def test_doctor_reports_missing_dependencies_without_touching_container_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for filename in ('hypr/hyprland.lua', 'quickshell/shell.qml'):
                path = root / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            etc = root / 'etc'
            etc.mkdir()
            for filename in ('subuid', 'subgid'):
                (etc / filename).write_text('alice:100000:65536\n')
            with patch.object(common.os, 'geteuid', return_value=1000), \
                    patch.object(system.os, 'getuid', return_value=1000), \
                    patch.object(system.getpass, 'getuser', return_value='alice'), \
                    patch.object(system, 'DESKTOP', root), \
                    patch.object(system, 'Path', side_effect=lambda name: etc if name == '/etc' else Path(name)), \
                    patch.object(system.subprocess, 'run',
                                 return_value=subprocess.CompletedProcess([], 0)) as run:
                with patch.object(system.shutil, 'which', side_effect=lambda tool: '/usr/bin/' + tool):
                    self.assertEqual(self.call(['doctor']), 0)
                    run.assert_called_once_with(['podman', 'info'], stdout=subprocess.DEVNULL, check=False)
                with patch.object(system.shutil, 'which', side_effect=lambda tool:
                                  None if tool == 'python3' else '/usr/bin/' + tool):
                    self.assertEqual(self.call(['doctor']), 1)


if __name__ == '__main__':
    unittest.main()
