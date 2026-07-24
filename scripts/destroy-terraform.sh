#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

printf "${GREEN}Infrastructure Destroy${RESET}\n"
terraform -chdir="$TF_DIR" destroy
printf "${GREEN} ⚒️ Infrastructure destroy correctly${RESET}\n"
