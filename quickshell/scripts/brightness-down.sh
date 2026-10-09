#!/usr/bin/env bash
# Decrease brightness by 5% on display 1
exec "$(dirname "$0")/brightness.sh" 1 - 5
