#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

printf "${GREEN}Infrastructure Deploy${RESET}\n"
terraform -chdir="$TF_DIR" init
terraform -chdir="$TF_DIR" fmt
terraform -chdir="$TF_DIR" validate
terraform -chdir="$TF_DIR" plan
terraform -chdir="$TF_DIR" apply
printf "${GREEN} ✅ Infrastructure deploy correctly${RESET}\n"
