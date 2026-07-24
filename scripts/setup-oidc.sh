#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

# Bootstraps GitHub Actions OIDC access to Azure for this repo, least privilege.
# Idempotent: safe to re-run, every step checks existence before creating.
#
# Client-side JMESPath filtering (--all + [?...]) is used everywhere because
# this az CLI version rejects server-side --filter on Graph resources.
# Shared identifiers (RG, SA, GITHUB_REPO) come from _lib.sh.

APP_NAME="github-oidc-monitoring-tp"

# Federated credential suffixes, one per CI use case, keyed by credential name:
#   pull_request       -> the plan job on PRs
#   environment:...    -> the apply job, gated by the production environment
#   ref:refs/heads/... -> kept for any job running directly on main
# The subject prefix uses GitHub's immutable owner/repo IDs (rename-proof) and
# is fetched live below, so no numeric IDs are hardcoded here.
declare -A FED_SUFFIXES=(
  [github-pull-request]="pull_request"
  [github-env-production]="environment:production"
  [github-main]="ref:refs/heads/main"
)

# Built-in role definition GUIDs Terraform assigns (Prometheus VM + Grafana).
# The RBAC Administrator condition below is restricted to exactly these, so the
# identity can never grant itself anything broader.
# Verify with: az role definition list --name "<role>" --query "[0].name" -o tsv
ROLE_GUIDS="\
3913510d-42f4-4e42-8a64-420c390055eb, \
43d0d8ad-25c7-4714-9337-8ba259a9fe05, \
b0d8363b-8ddd-447d-831f-62ca05bff136, \
22926164-76b3-42b3-bc55-97df8dab3e41"
# Monitoring Metrics Publisher / Monitoring Reader / Monitoring Data Reader / Grafana Admin

die() { echo "$1" >&2; exit 1; }

get_app_id() {
  az ad app list --all --query "[?displayName=='${APP_NAME}'].appId | [0]" -o tsv
}

get_sp_oid() {
  az ad sp list --all --query "[?appId=='${1}'].id | [0]" -o tsv
}

# GitHub's immutable subject prefix for this repo (repo:owner@id/repo@id).
# Tokens are minted with these numeric IDs, so fed cred subjects must match.
get_sub_prefix() {
  gh api "repos/${GITHUB_REPO}/actions/oidc/customization/sub" --jq .sub_claim_prefix
}

# Create the app registration if absent, echo its appId.
ensure_app() {
  local app_id
  app_id=$(get_app_id)
  if [ -z "$app_id" ]; then
    app_id=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  fi
  [ -n "$app_id" ] || die "APP_ID empty after create"
  echo "$app_id"
}

# Create the service principal if absent, echo its object id.
ensure_sp() {
  local app_id="$1" sp_oid
  sp_oid=$(get_sp_oid "$app_id")
  if [ -z "$sp_oid" ]; then
    az ad sp create --id "$app_id" >/dev/null
    sp_oid=$(get_sp_oid "$app_id")
  fi
  [ -n "$sp_oid" ] || die "SP_OID empty after create"
  echo "$sp_oid"
}

# Create one federated credential (name, subject) if absent.
ensure_federated_credential() {
  local app_id="$1" name="$2" subject="$3" existing
  existing=$(az ad app federated-credential list --id "$app_id" \
    --query "[?name=='${name}'].name | [0]" -o tsv)
  [ -n "$existing" ] && return 0
  az ad app federated-credential create --id "$app_id" --parameters "{
    \"name\": \"${name}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${subject}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" >/dev/null
}

# Contributor on the RG: deploy resources. Scoped to the RG only.
assign_deploy_role() {
  az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal \
    --role "Contributor" --scope "$2"
}

# Storage Blob Data Contributor on the storage account: read/write the tfstate.
assign_state_role() {
  az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" --scope "$2"
}

# RBAC Administrator constrained to the four roles Terraform assigns only, so
# the identity can never assign itself Owner or anything else.
assign_rbac_role() {
  az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal \
    --role "Role Based Access Control Administrator" --scope "$2" \
    --condition-version "2.0" \
    --condition "(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
 )
 OR
 (
  @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ROLE_GUIDS}}
 )
) AND (
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
 )
 OR
 (
  @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ROLE_GUIDS}}
 )
)"
}

print_github_vars() {
  echo "done. put these in GitHub repo variables:"
  echo "  AZURE_CLIENT_ID=$1"
  echo "  AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
  echo "  AZURE_SUBSCRIPTION_ID=$2"
}

main() {
  local app_id sp_oid sub_id rg_scope sa_scope
  app_id=$(ensure_app);            echo "APP_ID=$app_id"
  sp_oid=$(ensure_sp "$app_id");   echo "SP_OID=$sp_oid"
  local prefix
  prefix=$(get_sub_prefix)
  [ -n "$prefix" ] || die "could not fetch OIDC subject prefix (is gh authenticated?)"
  for name in "${!FED_SUFFIXES[@]}"; do
    ensure_federated_credential "$app_id" "$name" "${prefix}:${FED_SUFFIXES[$name]}"
  done

  sub_id=$(az account show --query id -o tsv)
  rg_scope="/subscriptions/${sub_id}/resourceGroups/${RG}"
  sa_scope="${rg_scope}/providers/Microsoft.Storage/storageAccounts/${SA}"

  assign_deploy_role "$sp_oid" "$rg_scope"
  assign_state_role  "$sp_oid" "$sa_scope"
  assign_rbac_role   "$sp_oid" "$rg_scope"

  print_github_vars "$app_id" "$sub_id"
}

main "$@"
