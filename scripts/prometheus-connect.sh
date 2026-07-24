#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ip="$(tf_output prometheus_vm_public_ip)"
if [ -z "$ip" ]; then
	printf "${RED}Error: Prometheus IP not found (empty/locked state or infra not deployed).${RESET}\n" >&2
	exit 1
fi

printf "${GREEN}Connecting to Prometheus VM: %s${RESET}\n" "$ip"
ssh "azureuser@$ip"
