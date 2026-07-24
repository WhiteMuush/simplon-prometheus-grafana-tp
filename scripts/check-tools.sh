#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

command -v terraform >/dev/null 2>&1 || {
	printf "${RED}Error: terraform not found in PATH.${RESET}\n" >&2
	exit 1
}
