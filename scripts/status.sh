#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

count="$( (terraform -chdir="$TF_DIR" state list 2>/dev/null || true) | wc -l )"
if [ "$count" -eq 0 ]; then
	printf "${RED}No infrastructure deployed (empty, locked or inaccessible state).${RESET}\n"
	exit 0
fi

ip="$(tf_output prometheus_vm_public_ip)"
grafana="$(tf_output grafana_endpoint)"
appurl="$(tf_output app_service_url)"

printf "${GREEN}%s resources deployed${RESET}\n" "$count"
printf "Prometheus VM : %s\n" "${ip:-n/a}"
printf "Grafana       : %s\n" "${grafana:-n/a}"
printf "App Service   : %s\n" "${appurl:-n/a}"
