"""Check completion notifications without writing to GitHub."""

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('personal_notifications',
                                            ROOT / 'build_files/ci/dispatch-personal-images.py')
notifications = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notifications)


class NotificationTests(unittest.TestCase):
    def test_destinations_are_validated_and_deduplicated(self):
        self.assertEqual(notifications.targets('person/one\nperson/two person/one'), ['person/one', 'person/two'])
        with self.assertRaises(ValueError):
            notifications.targets('person/one https://github.com/person/two')

    def test_one_failure_does_not_prevent_other_destinations(self):
        calls = []
        class Response:
            status = 204
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
        def opener(request, **kwargs):
            calls.append(request)
            if len(calls) == 1:
                raise OSError('destination unavailable')
            return Response()
        self.assertEqual(notifications.dispatch(['private/one', 'private/two'], 'test-token', 42, 2, opener), 1)
        self.assertEqual(len(calls), 2)
        self.assertEqual(json.loads(calls[1].data), {'event_type': 'avethyos-published', 'client_payload': {
            'upstream_repository': '5aether/avethyos', 'run_id': 42, 'run_attempt': 2}})
        self.assertTrue(calls[1].full_url.endswith('/repos/private/two/dispatches'))


if __name__ == '__main__':
    unittest.main()
