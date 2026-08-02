#!/usr/bin/env bash
# One-time setup: federate a Microsoft Entra app registration with GitHub
# Actions OIDC so ci-infra.yml (and the cd-*.yml workflows) can authenticate
# without a client secret. Run this locally with an account that can create
# app registrations and role assignments (e.g. Application Administrator +
# a role assignment right on the target scope).
#
# Usage:
#   OWNER=my-org REPO=contoso-retail BRANCH=main ./setup-github-oidc.sh
#
# Re-run is safe: az ad app federated-credential create fails if a credential
# with the same --name already exists, so bump the name or delete first.
set -euo pipefail

OWNER="${OWNER:?Set OWNER to the GitHub org/user, e.g. contoso-org}"
REPO="${REPO:?Set REPO to the GitHub repo name, e.g. contoso-retail}"
BRANCH="${BRANCH:-main}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-gh-oidc-contoso-retail}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID to the target Azure subscription}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-contoso-dev-eus2}"

echo "== Creating app registration: $APP_DISPLAY_NAME =="
APP_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
echo "APP_ID=$APP_ID"

echo "== Creating service principal for the app =="
az ad sp create --id "$APP_ID" >/dev/null

echo "== Federated credential: pull_request (used by ci-infra.yml's what-if job) =="
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"gh-${REPO}-pull-request\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${OWNER}/${REPO}:pull_request\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

echo "== Federated credential: push to ${BRANCH} (used by cd-*.yml on merge) =="
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"gh-${REPO}-branch-${BRANCH}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${OWNER}/${REPO}:ref:refs/heads/${BRANCH}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

echo "== Federated credential: workflow_dispatch (manual runs from any ref) =="
echo "   NOTE: GitHub does not expose a distinct subject for workflow_dispatch —"
echo "   it reuses the triggering ref's subject, already covered by the branch"
echo "   credential above. Add more branch/environment credentials as needed,"
echo "   e.g. for test/prod protected environments:"
echo "     subject: repo:${OWNER}/${REPO}:environment:test"

echo "== Role assignment: Contributor on ${RESOURCE_GROUP} (least privilege for what-if + deploy) =="
az role assignment create \
  --assignee "$APP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

echo
echo "== Done. Set these as GitHub Actions *variables* (not secrets — no secret exists): =="
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "  gh variable set AZURE_CLIENT_ID       --body \"$APP_ID\""
echo "  gh variable set AZURE_TENANT_ID       --body \"$TENANT_ID\""
echo "  gh variable set AZURE_SUBSCRIPTION_ID --body \"$SUBSCRIPTION_ID\""
