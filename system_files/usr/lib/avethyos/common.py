"""Shared command execution; arguments stay separate and never enter a shell."""
import os
from pathlib import Path
import subprocess


DESKTOP = Path('/usr/share/avethyos')


def run(arguments, *, admin=False, **kwargs):
    if admin and os.geteuid() != 0:
        arguments = ['sudo', *arguments]
    subprocess.run(arguments, check=True, **kwargs)


def user_only():
    if os.geteuid() == 0:
        raise ValueError('Run this command as your normal user, without sudo.')


def xdg(variable, fallback):
    value = os.environ.get(variable, '')
    return Path(value) if value.startswith('/') else Path.home() / fallback
