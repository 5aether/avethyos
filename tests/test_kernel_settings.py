"""Verify machine preferences without touching the host's bootloader or /etc."""

import importlib.machinery
import importlib.util
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'system_files/usr/lib/avethyos/kernel.py'
loader = importlib.machinery.SourceFileLoader('kernel_settings', str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
settings = importlib.util.module_from_spec(spec)
loader.exec_module(settings)


class KernelSettingsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'etc/avethyos/kernel-arguments.json'
        self.calls = []
        self.fail = False

    def backend(self, command, **kwargs):
        self.calls.append(command)
        failed = self.fail and command[-1] != '--help'
        return subprocess.CompletedProcess(command, int(failed), '',
                                           'boot partition unavailable' if failed else '')

    def stage(self, operation, *arguments):
        settings.stage(operation, list(arguments), self.path, self.backend)

    def test_replace_one_setting_preserves_other_and_repeated_arguments(self):
        self.stage('set', 'hid_apple.fnmode=1', 'quiet', 'console=tty0', 'console=ttyS0')
        self.stage('set', 'hid_apple.fnmode=2')
        self.assertEqual(settings.load(self.path)['arguments'],
                         ['quiet', 'console=tty0', 'console=ttyS0', 'hid_apple.fnmode=2'])
        self.assertEqual(self.calls[-1], [settings.BOOTC, 'loader-entries',
                         'set-options-for-source', '--source', 'avethyos-user', '--options',
                         'quiet console=tty0 console=ttyS0 hid_apple.fnmode=2'])
        self.assertFalse(settings.load(self.path)['pending'])

    def test_remove_exact_value_and_then_entire_key(self):
        self.stage('add', 'console=tty0', 'console=ttyS0', 'quiet')
        self.stage('remove', 'console=tty0')
        self.assertEqual(settings.load(self.path)['arguments'], ['console=ttyS0', 'quiet'])
        self.stage('remove', 'console')
        self.assertEqual(settings.load(self.path)['arguments'], ['quiet'])

    def test_reset_clears_only_our_native_source(self):
        self.stage('set', 'quiet')
        self.stage('reset')
        self.assertEqual(self.calls[-1], [settings.BOOTC, 'loader-entries',
                         'set-options-for-source', '--source', 'avethyos-user'])
        self.assertEqual(settings.load(self.path)['arguments'], [])

    def test_backend_failure_is_visible_and_preferences_can_be_retried(self):
        self.stage('set', 'quiet')
        self.fail = True
        with self.assertRaisesRegex(RuntimeError, 'kernel apply'):
            self.stage('set', 'hid_apple.fnmode=2')
        saved = settings.load(self.path)
        self.assertTrue(saved['pending'])
        self.assertEqual(saved['arguments'], ['quiet', 'hid_apple.fnmode=2'])
        self.fail = False
        self.stage('apply')
        self.assertEqual(self.calls[-1][-1], 'quiet hid_apple.fnmode=2')
        self.assertFalse(settings.load(self.path)['pending'])

    def test_missing_native_api_keeps_previous_preferences(self):
        self.stage('set', 'quiet')
        before = self.path.read_bytes()
        def unsupported(command, **kwargs):
            return subprocess.CompletedProcess(command, 1, '', 'unknown command')
        with self.assertRaisesRegex(RuntimeError, 'Upgrade AvethyOS'):
            settings.stage('set', ['debug'], self.path, unsupported)
        self.assertEqual(self.path.read_bytes(), before)

    def test_unsafe_serialization_is_rejected_before_backend_or_save(self):
        for argument in ('a=b c=d', 'a=\n', 'a="value"', '=value', 'a=\\value'):
            with self.subTest(argument=argument), self.assertRaises(ValueError):
                self.stage('set', argument)
        self.assertFalse(self.path.exists())
        self.assertEqual(self.calls, [])

    def test_shell_punctuation_is_data(self):
        self.stage('set', 'test=$(touch;/tmp/not-a-command)', 'video=DP-1:1920x1080@60')
        self.assertEqual(self.calls[-1][-1],
                         'test=$(touch;/tmp/not-a-command) video=DP-1:1920x1080@60')

    def test_fnmode_uses_module_qualified_argument_and_default_removes_it(self):
        with patch.object(settings.os, 'geteuid', return_value=0), patch.object(settings, 'stage') as stage:
            settings.handle(argparse.Namespace(command='fnmode', mode='2'))
            stage.assert_called_once_with('set', ['hid_apple.fnmode=2'])
            stage.reset_mock()
            settings.handle(argparse.Namespace(command='fnmode', mode='default'))
            stage.assert_called_once_with('remove', ['hid_apple.fnmode'])

    def test_invalid_saved_arguments_are_rejected(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text(json.dumps({'version': 1, 'arguments': ['a=b c=d'], 'pending': False}))
        with self.assertRaises(ValueError):
            self.stage('apply')
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
