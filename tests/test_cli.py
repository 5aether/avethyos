"""Exercise settings, privilege boundaries, and command routing without touching the host."""
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


MODULES = Path(__file__).resolve().parents[1] / 'system_files/usr/lib/avethyos'
sys.path.insert(0, str(MODULES))
import cli
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


if __name__ == '__main__':
    unittest.main()
