#!/usr/bin/python3
"""Notify opt-in repositories after both AvethyOS variants have been released."""

import json
import os
import re
import sys
import urllib.request


def targets(value):
    repositories = value.split()
    if any(not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo)
           for repo in repositories):
        raise ValueError('PERSONAL_IMAGE_REPOS must contain whitespace-separated OWNER/REPO names.')
    return list(dict.fromkeys(repositories))


def dispatch(repositories, token, run_id, run_attempt, opener=urllib.request.urlopen):
    failures = 0
    for repository in repositories:
        request = urllib.request.Request(
            f'https://api.github.com/repos/{repository}/dispatches',
            data=json.dumps({'event_type': 'avethyos-published', 'client_payload': {
                'upstream_repository': '5aether/avethyos',
                'run_id': int(run_id), 'run_attempt': int(run_attempt)}}).encode(),
            headers={'Accept': 'application/vnd.github+json',
                     'Authorization': f'Bearer {token}',
                     'X-GitHub-Api-Version': '2022-11-28',
                     'Content-Type': 'application/json'}, method='POST')
        try:
            with opener(request, timeout=30) as response:
                if response.status != 204:
                    raise RuntimeError('Unexpected dispatch response')
        except (OSError, RuntimeError):
            # Destination repository names may be private; report counts only.
            failures += 1
    return failures


def main():
    repositories = targets(os.environ.get('PERSONAL_IMAGE_REPOS', ''))
    token = os.environ.get('PERSONAL_IMAGE_DISPATCH_TOKEN', '')
    if not repositories or not token:
        print('Immediate personal-image notifications are not configured; scheduled checks remain available.')
        return 0
    failures = dispatch(repositories, token, os.environ['UPSTREAM_RUN_ID'],
                        os.environ['UPSTREAM_RUN_ATTEMPT'])
    print(f'Personal-image notifications: {len(repositories) - failures} sent, {failures} failed.')
    if failures:
        print('::warning::Check the dispatch token and destination default branches. Scheduled checks remain available.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError) as error:
        print(f'::warning::{error}', file=sys.stderr)
        sys.exit(1)
