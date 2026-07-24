#!/usr/bin/env bash
set -euo pipefail

# Bootstraps GitHub Actions OIDC access to Azure for this repo, least privilege.
# Idempotent: safe to re-run, every step checks existence before creating.
#
# Client-side JMESPath filtering (--all + [?...]) is used everywhere because
# this az CLI version rejects server-side --filter on Graph resources.

APP_NAME="github-oidc-monitoring-tp"
REPO="WhiteMuush/simplon-prometheus-grafana-tp"
SUBJECT="repo:${REPO}:ref:refs/heads/main"
RG="mpetitRG"
SA="stmpetittfstate"

# Built-in role definition GUIDs Terraform assigns to the Prometheus VM identity.
# Verify with: az role definition list --name "<role>" --query "[0].name" -o tsv
PUBLISHER="3913510d-42f4-4e42-8a64-420c390055eb"   # Monitoring Metrics Publisher
MON_READER="43d0d8ad-25c7-4714-9337-8ba259a9fe05"  # Monitoring Reader

die() { echo "$1" >&2; exit 1; }

get_app_id() {
  az ad app list --all --query "[?displayName=='${APP_NAME}'].appId | [0]" -o tsv
}

get_sp_oid() {
  az ad sp list --all --query "[?appId=='${1}'].id | [0]" -o tsv
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

# Create the federated credential trusting only pushes to main, if absent.
ensure_federated_credential() {
  local app_id="$1" existing
  existing=$(az ad app federated-credential list --id "$app_id" \
    --query "[?subject=='${SUBJECT}'].name | [0]" -o tsv)
  [ -n "$existing" ] && return 0
  az ad app federated-credential create --id "$app_id" --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${SUBJECT}\",
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

# RBAC Administrator constrained to the two monitoring roles only, so the
# identity can never assign itself Owner or anything else.
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
  @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${PUBLISHER}, ${MON_READER}}
 )
) AND (
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
 )
 OR
 (
  @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${PUBLISHER}, ${MON_READER}}
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
  ensure_federated_credential "$app_id"

  sub_id=$(az account show --query id -o tsv)
  rg_scope="/subscriptions/${sub_id}/resourceGroups/${RG}"
  sa_scope="${rg_scope}/providers/Microsoft.Storage/storageAccounts/${SA}"

  assign_deploy_role "$sp_oid" "$rg_scope"
  assign_state_role  "$sp_oid" "$sa_scope"
  assign_rbac_role   "$sp_oid" "$rg_scope"

  print_github_vars "$app_id" "$sub_id"
}

main "$@"
