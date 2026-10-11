#!/usr/bin/python3
"""Request rebuilds in configured private repos after AvethyOS publishes."""

import json
import os
import re
import sys
import urllib.request


def targets(value):
    result = value.split()
    for repository in result:
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('PERSONAL_IMAGE_REPOS must contain OWNER/REPO names separated by whitespace')
    return list(dict.fromkeys(result))


def main():
    token = os.environ.get('PERSONAL_IMAGE_DISPATCH_TOKEN', '')
    repositories = targets(os.environ.get('PERSONAL_IMAGE_REPOS', ''))
    if not token or not repositories:
        print('No personal-image notifications configured.')
        return
    failures = 0
    for repository in repositories:
        request = urllib.request.Request(
            f'https://api.github.com/repos/{repository}/actions/workflows/build.yml/dispatches',
            data=json.dumps({'ref': 'main', 'inputs': {'force': False}}).encode(),
            headers={'Accept': 'application/vnd.github+json',
                     'Authorization': 'Bearer ' + token,
                     'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json'},
            method='POST')
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                if response.status != 204:
                    raise RuntimeError(f'Unexpected HTTP {response.status}')
        except (OSError, RuntimeError):
            # Keep private destination names out of the public upstream logs.
            failures += 1
    if failures:
        raise RuntimeError(f'{failures} personal-image notifications failed. Check the token, '
                           'repository names and main branches. Scheduled checks remain available.')
    print(f'Notified {len(repositories)} personal-image repositories.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
