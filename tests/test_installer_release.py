import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / 'build_files/ci/installer-release.py'
spec = importlib.util.spec_from_file_location('installer_release', HELPER)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerReleaseTests(unittest.TestCase):
    def setUp(self):
        self.repository = 'owner/private-avethyos'
        self.revision = 'a' * 40
        self.run = {'path': '.github/workflows/build.yml', 'status': 'completed',
                    'conclusion': 'success', 'head_branch': 'main', 'event': 'push',
                    'head_repository': {'full_name': self.repository}}
        self.jobs = [{'name': f'Validate and release {variant}', 'conclusion': 'success',
                      'steps': [{'name': 'Promote the verified digest to update tags',
                                 'conclusion': 'success'}]}
                     for variant in ('standard', 'nvidia')]
        self.metadata = {'Os': 'linux', 'Architecture': 'amd64', 'Digest': 'sha256:' + 'b' * 64,
                         'Labels': {'io.avethyos.variant': 'standard',
                                    'org.opencontainers.image.revision': self.revision,
                                    'org.opencontainers.image.source': f'https://github.com/{self.repository}',
                                    'containers.bootc': '1'}}

    def test_both_successful_promotions_are_required(self):
        installer.released(self.run, self.jobs, self.repository)
        for change in ('failure', 'skipped'):
            jobs = copy.deepcopy(self.jobs)
            jobs[1]['steps'][0]['conclusion'] = change
            with self.assertRaises(ValueError):
                installer.released(self.run, jobs, self.repository)

    def test_missing_or_duplicate_variant_jobs_are_rejected(self):
        for jobs in (self.jobs[:1], self.jobs + self.jobs[:1]):
            with self.assertRaises(ValueError):
                installer.released(self.run, jobs, self.repository)

    def test_pr_foreign_branch_and_failed_runs_are_rejected(self):
        for field, value in (('event', 'pull_request'), ('status', 'in_progress'),
                             ('conclusion', 'failure'), ('head_branch', 'feature'),
                             ('path', '.github/workflows/build-disk.yml'),
                             ('head_repository', {'full_name': 'untrusted/fork'})):
            run = dict(self.run, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                installer.released(run, self.jobs, self.repository)

    def test_scheduled_and_manual_releases_work(self):
        for event in ('schedule', 'workflow_dispatch'):
            installer.released(dict(self.run, event=event), self.jobs, self.repository)

    def test_exact_digest_is_preserved(self):
        image = 'ghcr.io/owner/avethyos'
        self.assertEqual(installer.image_reference(self.metadata, image, 'standard',
                                                  self.revision, self.repository),
                         image + '@sha256:' + 'b' * 64)

    def test_wrong_platform_and_invalid_digest_are_rejected(self):
        for field, value in (('Os', 'windows'), ('Architecture', 'arm64'), ('Digest', 'latest')):
            metadata = dict(self.metadata, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                installer.image_reference(metadata, 'image', 'standard', self.revision, self.repository)

    def test_other_image_variant_revision_and_repository_are_rejected(self):
        for field, value in (('io.avethyos.variant', 'nvidia'),
                             ('org.opencontainers.image.revision', 'c' * 40),
                             ('org.opencontainers.image.source', 'https://github.com/foreign/repo'),
                             ('containers.bootc', '0')):
            metadata = copy.deepcopy(self.metadata)
            metadata['Labels'][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                installer.image_reference(metadata, 'image', 'standard', self.revision, self.repository)

    def test_configuration_is_parsed_without_executing_shell(self):
        self.assertEqual(installer.image_name('IMAGE_NAME="My-AvethyOS"\n'), 'my-avethyos')
        for configuration in ('IMAGE_NAME=$(touch /tmp/example)', 'IMAGE_NAME=one; echo two',
                              'IMAGE_NAME=one\nIMAGE_NAME=two\n'):
            with self.assertRaises(ValueError):
                installer.image_name(configuration)

    def test_forks_keep_their_configured_update_tag(self):
        for configured, variant, expected in (
                ('latest', 'standard', 'latest'), ('latest', 'nvidia', 'nvidia'),
                ('stable', 'standard', 'stable'), ('stable', 'nvidia', 'stable-nvidia')):
            self.assertEqual(installer.update_tag(f'DEFAULT_TAG="{configured}"\n', variant), expected)
        for configured in ('.invalid', 'a' * 129):
            with self.assertRaises(ValueError):
                installer.update_tag(f'DEFAULT_TAG="{configured}"\n', 'standard')

    def test_private_digest_pull_keeps_credentials_out_of_builder(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            fake_podman = temporary / 'podman'
            fake_podman.write_text('''#!/usr/bin/python3
import json, os
from pathlib import Path
import sys
args = sys.argv[1:]
with open(os.environ['TEST_PODMAN_LOG'], 'a') as output:
    output.write(json.dumps(args) + '\\n')
if args[:2] == ['image', 'exists']:
    sys.exit(1)
if args[0] == 'run':
    mount = next(args[index + 1] for index, value in enumerate(args)
                 if value == '-v' and args[index + 1].endswith(':/output'))
    output = Path(mount.removesuffix(':/output')) / 'bootiso'
    output.mkdir()
    (output / 'install.iso').write_bytes(b'isolated installer fixture')
''')
            fake_podman.chmod(0o755)
            fake_sudo = temporary / 'sudo'
            fake_sudo.write_text('#!/bin/sh\nexec "$@"\n')
            fake_sudo.chmod(0o755)
            authfile = temporary / 'auth.json'
            authfile.write_text('{"auths":{"ghcr.io":{"auth":"fixture"}}}')
            output = temporary / 'output'
            log = temporary / 'commands.jsonl'
            source = 'ghcr.io/owner/private-os@sha256:' + 'b' * 64
            environment = dict(os.environ, PATH=f'{temporary}:{os.environ["PATH"]}',
                               TEST_PODMAN_LOG=str(log), REGISTRY_AUTH_FILE=str(authfile),
                               ISO_SOURCE_REF=source)
            subprocess.run(['bash', 'build_files/build-iso.sh', 'ghcr.io/owner/private-os',
                            'nvidia', str(output)], cwd=HELPER.parents[2],
                           env=environment, check=True, capture_output=True, text=True)
            commands = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertIn(['pull', '--retry=3', '--authfile', str(authfile), source], commands)
            self.assertIn(['tag', source, 'ghcr.io/owner/private-os:nvidia'], commands)
            builder = next(command for command in commands if command[0] == 'run')
            self.assertEqual(builder[-1], 'ghcr.io/owner/private-os:nvidia')
            self.assertNotIn(str(authfile), ' '.join(builder))
            self.assertNotIn('--authfile', builder)
            self.assertEqual((output / 'bootiso/install.iso').read_bytes(),
                             b'isolated installer fixture')


if __name__ == '__main__':
    unittest.main()
