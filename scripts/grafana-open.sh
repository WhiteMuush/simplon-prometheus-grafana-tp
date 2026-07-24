#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

url="$(tf_output grafana_endpoint)"
if [ -z "$url" ]; then
	printf "${RED}Error: Grafana URL not found (empty/locked state or infra not deployed).${RESET}\n" >&2
	exit 1
fi

printf "${GREEN}Grafana: %s${RESET}\n" "$url"
