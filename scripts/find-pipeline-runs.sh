#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: find-pipeline-runs.sh [--help]

Find Azure DevOps build and YAML pipeline runs queued by a user on a UTC day.
Requires Azure CLI with the azure-devops extension, and jq.
Sign in with az login --allow-no-subscriptions or supply an Azure DevOps PAT
through AZURE_DEVOPS_EXT_PAT.

Required environment variables:
  ORG          Azure DevOps organisation name
  PROJECT      Project name or ID
  USER_EMAIL   Email to match against the run requester's identity

Optional environment variables:
  DAY          UTC date in YYYY-MM-DD format (default: 2026-11-17)
  MANUAL_ONLY  Set to false to include non-manual runs (default: true)

Example:
  ORG=my-organisation PROJECT=my-project USER_EMAIL=colleague@company.com \
    DAY=2026-11-17 ./scripts/find-pipeline-runs.sh
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
(( $# == 0 )) || die 'Unexpected arguments. Run with --help for usage.'

: "${ORG:?Set ORG}"
: "${PROJECT:?Set PROJECT}"
: "${USER_EMAIL:?Set USER_EMAIL}"

DAY="${DAY:-2026-11-17}"
MANUAL_ONLY="${MANUAL_ONLY:-true}"
PAGE_SIZE=1000

for cmd in az jq; do
  command -v "$cmd" >/dev/null || die "Missing dependency: $cmd"
done

if ! az extension show --name azure-devops --output none; then
  die 'Cannot load the Azure DevOps extension. If missing, install it with: az extension add --name azure-devops'
fi

[[ "$DAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
  die 'Invalid DAY. Use YYYY-MM-DD.'
next_day="$(jq -ner --arg day "$DAY" '
  ($day + "T00:00:00Z" | fromdateiso8601) as $start
  | select(($start | strftime("%Y-%m-%d")) == $day)
  | $start + 86400 | todateiso8601
' 2>/dev/null)" || die 'Invalid DAY. Use a valid UTC date in YYYY-MM-DD format.'

[[ "$MANUAL_ONLY" == true || "$MANUAL_ONLY" == false ]] ||
  die 'MANUAL_ONLY must be true or false.'

ORG_URL="https://dev.azure.com/$ORG"

if ! az devops project list \
  --organization "$ORG_URL" \
  --top 1 \
  --output none; then
  die "Cannot verify Azure DevOps access to '$ORG'. Check the organisation name and access. Sign in with 'az login --allow-no-subscriptions' or set AZURE_DEVOPS_EXT_PAT to an Azure DevOps PAT."
fi

printf 'Azure DevOps organisation access verified.\n' >&2

if ! az devops project show \
  --organization "$ORG_URL" \
  --project "$PROJECT" \
  --output none; then
  die "Cannot access project '$PROJECT'. Check your Azure CLI sign-in and project permissions."
fi

printf 'Project access verified.\n' >&2

params=(
  "minTime=${DAY}T00:00:00Z"
  "maxTime=$next_day"
  'queryOrder=queueTimeDescending'
  "\$top=$PAGE_SIZE"
)

if [[ "$MANUAL_ONLY" == true ]]; then
  params+=('reasonFilter=manual')
fi

if ! response="$(
  az devops invoke \
    --organization "$ORG_URL" \
    --area build \
    --resource builds \
    --route-parameters "project=$PROJECT" \
    --query-parameters "${params[@]}" \
    --api-version 7.1 \
    --http-method GET \
    --output json
)"; then
  die 'Build API request failed. Check your Azure CLI sign-in and build permissions.'
fi

count="$(jq -er '
  select(type == "object" and (.count | type == "number") and (.value | type == "array"))
  | .value | length
' <<< "$response")" || die 'Unexpected Build API response.'

if (( count >= PAGE_SIZE )) || jq -e '.continuation_token // "" | length > 0' <<< "$response" >/dev/null; then
  die "Search is incomplete. The Build API reached the $PAGE_SIZE-run limit or indicated another page."
fi

printf 'Examined %s accessible runs.\n' "$count" >&2

jq -r --arg email "$USER_EMAIL" --arg day "$DAY" '
  [
    .value[]
    | select((.requestedBy.uniqueName // "" | ascii_downcase) == ($email | ascii_downcase))
    | select(.queueTime | startswith($day + "T"))
  ] as $matches
  | if ($matches | length) == 0 then
      "No matching runs found."
    else
      (["Queued", "Pipeline", "Run ID", "Result", "URL"] | @tsv),
      ($matches[] | [
        .queueTime,
        .definition.name,
        (.id | tostring),
        (.result // .status // "unknown"),
        (._links.web.href // "")
      ] | @tsv)
    end
' <<< "$response"
