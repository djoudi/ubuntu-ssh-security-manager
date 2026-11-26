#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n ubuntu-ssh-security-manager.sh
printf '%s\n' 'Syntaxe Bash : OK'
