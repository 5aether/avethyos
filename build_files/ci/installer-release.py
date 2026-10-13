#!/usr/bin/python3
"""Resolve installers only from successful, fully published image releases."""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.request


def api(repository, path):
    request = urllib.request.Request(
        f'https://api.github.com/repos/{repository}/{path}',
        headers={'Accept': 'application/vnd.github+json',
                 'Authorization': f'Bearer {os.environ["GH_TOKEN"]}',
                 'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def released(run, jobs, repository):
    if (run.get('path') != '.github/workflows/build.yml'
            or run.get('status') != 'completed'
            or run.get('conclusion') != 'success'
            or run.get('head_branch') != 'main'
            or run.get('event') not in ('push', 'schedule', 'workflow_dispatch')
            or run.get('head_repository', {}).get('full_name') != repository):
        raise ValueError('Installers require a successful published main image build.')
    for variant in ('standard', 'nvidia'):
        matches = [job for job in jobs if job.get('name') == f'Validate and release {variant}']
        if len(matches) != 1 or matches[0].get('conclusion') != 'success' or not any(
                step.get('name') == 'Promote the verified digest to update tags'
                and step.get('conclusion') == 'success'
                for step in matches[0].get('steps', [])):
            raise ValueError(f'The {variant} image was not fully released.')


def setting(configuration, key):
    matches = re.findall(rf'^{key}=[\"\']?([A-Za-z0-9_.-]+)[\"\']?\s*$', configuration, re.M)
    if len(matches) != 1:
        raise ValueError(f'The released image configuration has no valid {key}.')
    return matches[0]


def image_name(configuration):
    return setting(configuration, 'IMAGE_NAME').lower()


def update_tag(configuration, variant):
    tag = setting(configuration, 'DEFAULT_TAG')
    if variant == 'nvidia':
        tag = 'nvidia' if tag == 'latest' else f'{tag}-nvidia'
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}', tag):
        raise ValueError('The released image configuration has an invalid update tag.')
    return tag


def image_reference(metadata, image, variant, revision, repository):
    labels = metadata.get('Labels') or {}
    digest = metadata.get('Digest', '')
    if (metadata.get('Os') != 'linux' or metadata.get('Architecture') != 'amd64'
            or not re.fullmatch(r'sha256:[a-f0-9]{64}', digest)
            or labels.get('io.avethyos.variant') != variant
            or labels.get('org.opencontainers.image.revision') != revision
            or labels.get('org.opencontainers.image.source') != f'https://github.com/{repository}'
            or labels.get('containers.bootc') != '1'):
        raise ValueError('The released image does not match its build, variant or platform.')
    return f'{image}@{digest}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', default='')
    parser.add_argument('--variant', choices=('standard', 'nvidia'), required=True)
    parser.add_argument('--authfile', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    repository = os.environ['GITHUB_REPOSITORY']
    if args.run_id:
        if not args.run_id.isdigit():
            raise ValueError('The image build run ID must be a number.')
        run = api(repository, f'actions/runs/{args.run_id}')
    else:
        runs = api(repository, 'actions/workflows/build.yml/runs?branch=main&status=success&per_page=100')
        run = next((item for item in runs['workflow_runs'] if item.get('event') in (
            'push', 'schedule', 'workflow_dispatch')), None)
        if run is None:
            raise ValueError('No successful published image build is available.')
    run_id, attempt = run['id'], run['run_attempt']
    jobs = api(repository, f'actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100')['jobs']
    released(run, jobs, repository)
    revision = run['head_sha']
    configuration = api(repository, f'contents/image-template.env?ref={revision}')
    configuration = base64.b64decode(configuration['content']).decode()
    name = image_name(configuration)
    image = f'ghcr.io/{repository.split("/")[0].lower()}/{name}'
    candidate = f'{image}:build-{args.variant}-{run_id}-{attempt}'
    inspection = subprocess.run([
        'skopeo', 'inspect', '--authfile', args.authfile, '--retry-times=3',
        '--override-os=linux', '--override-arch=amd64', f'docker://{candidate}'],
        check=True, capture_output=True, text=True)
    source = image_reference(json.loads(inspection.stdout), image, args.variant, revision, repository)
    tag = update_tag(configuration, args.variant)
    values = {'ISO_SOURCE_REF': source, 'IMAGE_REF': image, 'DEFAULT_TAG': tag,
              'IMAGE_NAME': name, 'RELEASE_SHA': revision, 'RELEASE_RUN_ID': str(run_id),
              'RELEASE_RUN_ATTEMPT': str(attempt),
              'ISO_BASENAME': f'{name}-{args.variant}-{run_id}-{attempt}'}
    with open(args.output, 'a', encoding='utf-8') as output:
        for key, value in values.items():
            output.write(f'{key}={value}\n')
    print(json.dumps({'image': source, 'update_image': f'{image}:{tag}',
                      'variant': args.variant, 'revision': revision,
                      'build_run': run_id, 'build_attempt': attempt}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f'::error::{error}', file=sys.stderr)
        sys.exit(1)
