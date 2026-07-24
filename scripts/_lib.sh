# Shared helpers, sourced by every script in this folder.
# shellcheck shell=bash

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

# Repo layout, resolved from this file location (works from any cwd).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
APP_DIR="$REPO_ROOT/app"

# Read a terraform output, print empty string on any failure.
tf_output() {
	terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || true
}
