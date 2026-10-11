"""Verify upstream notifications without accessing GitHub or exposing destinations."""

import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'build_files/notify-personal-images.py'
spec = importlib.util.spec_from_file_location('notifications', SCRIPT)
notifications = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notifications)


class NotificationTests(unittest.TestCase):
    def test_no_configuration_is_a_noop(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(notifications.urllib.request, 'urlopen') as request:
            notifications.main()
            request.assert_not_called()

    def test_only_valid_repository_names_are_accepted_and_duplicates_are_removed(self):
        self.assertEqual(notifications.targets('owner/private\nowner/private owner/another'),
                         ['owner/private', 'owner/another'])
        for value in ('https://github.com/owner/repo', 'owner/repo?token=value', 'owner/repo/other'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                notifications.targets(value)

    def test_dispatches_main_without_forcing_unchanged_builds(self):
        environment = {'PERSONAL_IMAGE_REPOS': 'owner/secret-repo',
                       'PERSONAL_IMAGE_DISPATCH_TOKEN': 'private-token'}
        with patch.dict(os.environ, environment, clear=True), patch.object(notifications.urllib.request, 'urlopen') as request:
            request.return_value.__enter__.return_value.status = 204
            notifications.main()
            sent = request.call_args.args[0]
            self.assertEqual(sent.get_method(), 'POST')
            self.assertEqual(json.loads(sent.data), {'ref': 'main', 'inputs': {'force': False}})
            self.assertTrue(sent.full_url.endswith('/actions/workflows/build.yml/dispatches'))

    def test_one_failure_does_not_skip_other_destinations_or_expose_private_details(self):
        environment = {'PERSONAL_IMAGE_REPOS': 'owner/secret-one owner/secret-two',
                       'PERSONAL_IMAGE_DISPATCH_TOKEN': 'private-token'}
        with patch.dict(os.environ, environment, clear=True), patch.object(notifications.urllib.request, 'urlopen') as request:
            successful = unittest.mock.MagicMock()
            successful.__enter__.return_value.status = 204
            request.side_effect = [OSError('secret-one private-token'), successful]
            with self.assertRaises(RuntimeError) as error:
                notifications.main()
            self.assertEqual(request.call_count, 2)
            self.assertNotIn('secret-one', str(error.exception))
            self.assertNotIn('private-token', str(error.exception))


if __name__ == '__main__':
    unittest.main()
