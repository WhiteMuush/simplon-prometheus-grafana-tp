#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

url="$(tf_output app_service_url)"
if [ -z "$url" ]; then
	printf "${RED}Error: App Service URL not found (empty/locked state or infra not deployed).${RESET}\n" >&2
	exit 1
fi

printf "${GREEN}Stress test on %s (fires Prometheus + App Insights alerts)${RESET}\n" "$url"

printf "→ 20 requests on /error...\n"
for _ in $(seq 1 20); do curl -s "$url/error" >/dev/null || true; done

printf "→ 10 requests on /crash...\n"
for _ in $(seq 1 10); do curl -s "$url/crash" >/dev/null || true; done

printf "→ Checking log_erreurs_total counter:\n"
curl -s "$url/metrics" | grep log_erreurs_total \
	|| printf "${RED}(counter not exposed — is the Flask app actually deployed? run: make deploy-app)${RESET}\n"

printf "${GREEN}Done. Check Prometheus Explorer and App Insights → Failures.${RESET}\n"
