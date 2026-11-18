#!/usr/bin/env bats

setup() {
  FIND_RUNS="$BATS_TEST_DIRNAME/../scripts/find-pipeline-runs.sh"
  export ORG=my-organisation PROJECT=my-project
  export USER_EMAIL=colleague@company.com DAY=2026-11-17
  unset AZURE_DEVOPS_EXT_PAT
  export AZ_CALLS="$BATS_TEST_TMPDIR/az-calls"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/az" <<'MOCK'
#!/usr/bin/env bash
command="$1 $2"
if [[ "$2" == project ]]; then
  command+=" $3"
fi
printf '%s\n' "$command" >> "$AZ_CALLS"
case "$command" in
  'extension show') exit 0 ;;
  'account show') echo '{"name":"Test subscription"}'; exit 0 ;;
  'devops project list'|'devops project show'|'devops invoke') ;;
  *) exit 99 ;;
esac
if [[ "${AZURE_DEVOPS_EXT_PAT:-}" != fixture-pat ]]; then
  echo 'Before you can run Azure DevOps commands you need to run the login command (az login)' >&2
  exit 1
fi
if [[ "$2" == invoke ]]; then
  echo '{"count":0,"value":[]}'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/az"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "an Azure subscription can be selected while the organisation check fails" {
  run az account show
  [ "$status" -eq 0 ]

  run "$FIND_RUNS"

  [ "$status" -eq 1 ]
  [[ "$output" == *'Before you can run Azure DevOps commands'* ]]
  [ "$(cat "$AZ_CALLS")" = $'account show\nextension show\ndevops project list' ]
  [[ "$output" == *'az login --allow-no-subscriptions'* ]]
  [[ "$output" == *'AZURE_DEVOPS_EXT_PAT'* ]]
}

@test "an Azure DevOps PAT allows the search without a separate login command" {
  export AZURE_DEVOPS_EXT_PAT=fixture-pat
  run "$FIND_RUNS"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Azure DevOps organisation access verified.'* ]]
  [[ "$output" == *'No matching runs found.'* ]]
  [ "$(cat "$AZ_CALLS")" = $'extension show\ndevops project list\ndevops project show\ndevops invoke' ]
}
