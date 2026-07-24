#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

command -v az >/dev/null 2>&1 || {
	printf "${RED}Error: az CLI not found in PATH.${RESET}\n" >&2
	exit 1
}

app="$(tf_output app_service_url | sed -E 's#https?://##; s#\.azurewebsites\.net.*##')"
rg="$(tf_output resource_group_name)"
if [ -z "$app" ] || [ -z "$rg" ]; then
	printf "${RED}Error: app name or resource group not found (deploy the infra first).${RESET}\n" >&2
	exit 1
fi

printf "${GREEN}Deploying app code to %s (rg: %s)${RESET}\n" "$app" "$rg"
cd "$APP_DIR"
az webapp up --name "$app" --resource-group "$rg" --runtime "PYTHON:3.11"
