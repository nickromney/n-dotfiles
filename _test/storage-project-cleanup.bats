#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/cleanup-storage.sh"
  TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/storage-project-cleanup.XXXXXX")"
  TEST_TMP_DIR="$(cd "$TEST_TMP_DIR" && pwd -P)"
  export HOME="$TEST_TMP_DIR/home"
  export XDG_CACHE_HOME="$TEST_TMP_DIR/home-cache"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_OPTIONAL_LOCKS=0
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$TEST_TMP_DIR/projects"
  GIT_BIN="$(command -v git)"
}

teardown() {
  [ ! -d "$TEST_TMP_DIR" ] || chmod -R u+rwX "$TEST_TMP_DIR"
  rm -rf "$TEST_TMP_DIR"
}

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.name Fixture
  git -C "$1" config user.email fixture@example.invalid
  git -C "$1" config commit.gpgsign false
  printf 'original\n' > "$1/README.md"
  printf 'delete later\n' > "$1/delete-me.txt"
  printf '%s\n' 'node_modules/' '.venv/' '.build/' '.terraform/' '.env' 'data/' > "$1/.gitignore"
  git -C "$1" add README.md delete-me.txt .gitignore
  git -C "$1" commit -qm initial
}

put_file() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "${2:-fixture}" > "$1"
}

ignored_cache() { put_file "$1/node_modules/package/index.js" 'generated dependency'; }

assert_success() {
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

assert_refused() {
  [ "$status" -ne 0 ] || { printf '%s\n' "unexpected success: $output"; return 1; }
}

restore_archive() {
  local archive
  archive="$(find "$1" -type f -name '*.tar.gz' -print)"
  [ -n "$archive" ]
  [ "$(printf '%s\n' "$archive" | wc -l | tr -d ' ')" -eq 1 ]
  mkdir -p "$2"
  tar -xf "$archive" -C "$2"
}

@test "project preview and dry-run leave caches and archive destination untouched" {
  local repo="$TEST_TMP_DIR/projects/app" archive="$TEST_TMP_DIR/archives"
  new_repo "$repo"
  ignored_cache "$repo"
  run "$SCRIPT" --project-caches "$repo" --no-input
  assert_success
  [ -f "$repo/node_modules/package/index.js" ]
  run "$SCRIPT" --dry-run --project-caches "$repo" --no-input
  assert_success
  [ -f "$repo/node_modules/package/index.js" ]
  run "$SCRIPT" --dry-run --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_success
  [ ! -e "$archive" ]
  [ -f "$repo/README.md" ]
}

@test "project caches remove ignored dependencies but retain data and build evidence and repeat safely" {
  local repo="$TEST_TMP_DIR/projects/app with spaces"
  new_repo "$repo"
  ignored_cache "$repo"
  put_file "$repo/.venv/pyvenv.cfg"
  put_file "$repo/.venv/lib/module.py"
  put_file "$repo/.build/artifacts/compiler-output"
  put_file "$repo/.build/build.log" 'retain compiler failure evidence'
  put_file "$repo/.build/test-run.xcresult/Data/attachment" 'retain native test evidence'
  put_file "$repo/.env" 'local fixture configuration'
  put_file "$repo/data/project.sqlite" 'local fixture data'
  put_file "$repo/reports/check.txt" 'review result'
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  assert_success
  [ ! -e "$repo/node_modules" ]
  [ ! -e "$repo/.venv" ]
  [ -f "$repo/.build/build.log" ]
  [ -f "$repo/.build/test-run.xcresult/Data/attachment" ]
  [ -f "$repo/.env" ]
  [ -f "$repo/data/project.sqlite" ]
  [ -f "$repo/reports/check.txt" ]
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  assert_success
  [ -f "$repo/.build/build.log" ]
  [ -f "$repo/.build/test-run.xcresult/Data/attachment" ]
  [ -f "$repo/data/project.sqlite" ]
}

@test "project cache cleanup preserves tracked and nonignored untracked cache-like files" {
  local tracked="$TEST_TMP_DIR/projects/tracked" untracked="$TEST_TMP_DIR/projects/untracked"
  new_repo "$tracked"
  ignored_cache "$tracked"
  put_file "$tracked/node_modules/handwritten.js" 'tracked application code'
  git -C "$tracked" add -f node_modules/handwritten.js
  git -C "$tracked" commit -qm 'tracked dependency directory'
  new_repo "$untracked"
  printf '.env\n' > "$untracked/.gitignore"
  git -C "$untracked" add .gitignore
  git -C "$untracked" commit -qm 'do not ignore dependencies'
  ignored_cache "$untracked"
  run "$SCRIPT" --execute --project-caches "$tracked" --project-caches "$untracked" --no-input
  assert_success
  [ -f "$tracked/node_modules/handwritten.js" ]
  [ -f "$tracked/node_modules/package/index.js" ]
  [ -f "$untracked/node_modules/package/index.js" ]
  [[ "$output" == *"$tracked/node_modules"* ]] || { printf '%s\n' "$output"; return 1; }
  [[ "$output" == *"$untracked/node_modules"* ]] || { printf '%s\n' "$output"; return 1; }
}

@test "Terraform providers may be cleared without deleting state or environment metadata" {
  local repo="$TEST_TMP_DIR/projects/infrastructure"
  new_repo "$repo"
  put_file "$repo/.terraform/providers/provider.bin"
  put_file "$repo/.terraform/modules/downloaded/module.tf"
  put_file "$repo/.terraform/modules/modules.json" '{"Modules":[]}'
  put_file "$repo/.terraform/terraform.tfstate" 'backend metadata'
  put_file "$repo/.terraform/environment" 'development'
  put_file "$repo/terraform.tfstate" 'user-managed state'
  put_file "$repo/terraform.tfstate.backup" 'state backup'
  put_file "$repo/.terraform.lock.hcl" 'pinned providers'
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  assert_success
  [ ! -e "$repo/.terraform/providers" ]
  [ -f "$repo/.terraform/modules/modules.json" ]
  [ -f "$repo/.terraform/terraform.tfstate" ]
  [ -f "$repo/.terraform/environment" ]
  [ -f "$repo/terraform.tfstate" ]
  [ -f "$repo/terraform.tfstate.backup" ]
  [ -f "$repo/.terraform.lock.hcl" ]
}

@test "project cleanup clears only known scoped uv caches and retains unrelated cache state" {
  local repo="$TEST_TMP_DIR/projects/python-app"
  new_repo "$repo"
  printf '%s\n' '.uv-cache/' 'uv-cache/' '.cache/' >> "$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -qm 'ignore uv caches'
  put_file "$repo/.uv-cache/downloads/package.whl"
  put_file "$repo/uv-cache/downloads/package.whl"
  put_file "$repo/.cache/uv/downloads/package.whl"
  put_file "$repo/.cache/project-state/session.json" 'local user state'
  put_file "$XDG_CACHE_HOME/uv/owner-package.whl" 'global cache outside project scope'
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  assert_success
  [ ! -e "$repo/.uv-cache" ]
  [ ! -e "$repo/uv-cache" ]
  [ ! -e "$repo/.cache/uv" ]
  [ "$(cat "$repo/.cache/project-state/session.json")" = 'local user state' ]
  [ -f "$XDG_CACHE_HOME/uv/owner-package.whl" ]
}

@test "cache directories with a nested Git checkout retain that checkout and its dirty files" {
  local repo="$TEST_TMP_DIR/projects/app" nested
  new_repo "$repo"
  nested="$repo/node_modules/editable-package"
  new_repo "$nested"
  printf 'uncommitted library edit\n' >> "$nested/README.md"
  put_file "$nested/local-note.txt" 'untracked library note'
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  assert_success
  [ -d "$nested/.git" ]
  grep -q 'uncommitted library edit' "$nested/README.md"
  [ -f "$nested/local-note.txt" ]
  run git -C "$nested" status --porcelain=v1 -uall
  assert_success
  [[ "$output" == *" M README.md"* ]]
  [[ "$output" == *"?? local-note.txt"* ]]
}

@test "discovery skips synthetic Git markers and retains real nested checkouts" {
  local repo="$TEST_TMP_DIR/projects/outer" fake real
  new_repo "$repo"
  fake="$repo/fixture/project-000"
  put_file "$fake/.git/objects/aa/object" 'synthetic object'
  put_file "$fake/node_modules/package/index.js" 'fixture data must survive'
  real="$repo/nested-real"
  new_repo "$real"
  ignored_cache "$repo"
  ignored_cache "$real"
  run "$SCRIPT" --dry-run --project-caches "$repo" --no-input
  assert_success
  [[ "$output" == *"$repo/node_modules"* ]]
  [[ "$output" == *"$real/node_modules"* ]]
  [[ "$output" != *"Cache: $fake/node_modules"* ]]
  [ -f "$fake/.git/objects/aa/object" ]
  [ -f "$fake/node_modules/package/index.js" ]
  run "$SCRIPT" --dry-run --project-caches "$fake" --no-input
  assert_refused
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  assert_success
  [ ! -e "$repo/node_modules" ]
  [ ! -e "$real/node_modules" ]
  [ -f "$fake/.git/objects/aa/object" ]
  [ -f "$fake/node_modules/package/index.js" ]
}

@test "discovery retains linked worktrees and refuses malformed Git pointers" {
  local repo="$TEST_TMP_DIR/projects/outer" worktree="$TEST_TMP_DIR/projects/outer/worktree"
  new_repo "$repo"
  git -C "$repo" worktree add -q -b preview "$worktree"
  ignored_cache "$worktree"
  run "$SCRIPT" --dry-run --project-caches "$repo" --no-input
  assert_success
  [[ "$output" == *"$worktree/node_modules"* ]]
  put_file "$repo/broken/.git" 'gitdir: /no/such/location'
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  assert_refused
  [ -f "$worktree/node_modules/package/index.js" ]
}

@test "discovery preserves standalone non-repository markers and visits valid siblings" {
  local root="$TEST_TMP_DIR/projects" fake="$TEST_TMP_DIR/projects/gate-tree" repo="$TEST_TMP_DIR/projects/real"
  mkdir -p "$fake/.git"
  put_file "$fake/node_modules/package/index.js" 'fixture data must survive'
  new_repo "$repo"
  ignored_cache "$repo"
  run "$SCRIPT" --dry-run --project-caches "$root" --no-input
  assert_success
  [[ "$output" == *"$repo/node_modules"* ]]
  [[ "$output" != *"Cache: $fake/node_modules"* ]]
  run "$SCRIPT" --dry-run --project-caches "$fake" --no-input
  assert_refused
  run "$SCRIPT" --execute --project-caches "$root" --no-input
  assert_success
  [ ! -e "$repo/node_modules" ]
  [ -d "$fake/.git" ]
  [ -f "$fake/node_modules/package/index.js" ]
}

@test "discovery does not hide other Git inspection failures" {
  local root="$TEST_TMP_DIR/projects" repo="$TEST_TMP_DIR/projects/real" blocked="$TEST_TMP_DIR/projects/blocked"
  new_repo "$repo"
  ignored_cache "$repo"
  mkdir -p "$blocked/.git" "$TEST_TMP_DIR/bin"
  cat > "$TEST_TMP_DIR/bin/git" <<'STUB'
#!/bin/sh
case "$*" in *"/blocked"*) echo 'fatal: detected dubious ownership in repository' >&2; exit 128 ;; esac
exec "$REAL_GIT_BIN" "$@"
STUB
  chmod +x "$TEST_TMP_DIR/bin/git"
  run env PATH="$TEST_TMP_DIR/bin:$PATH" REAL_GIT_BIN="$GIT_BIN" "$SCRIPT" --execute --project-caches "$root" --no-input
  assert_refused
  [[ "$output" == *'dubious ownership'* ]]
  [ -f "$repo/node_modules/package/index.js" ]
  [ -d "$blocked/.git" ]
}

@test "a symlink at a project cache path never deletes its external contents" {
  local repo="$TEST_TMP_DIR/projects/app" external="$TEST_TMP_DIR/owner-data"
  new_repo "$repo"
  put_file "$external/keep.txt" 'owner data'
  ln -s "$external" "$repo/node_modules"
  run "$SCRIPT" --execute --project-caches "$repo" --no-input
  [ -L "$repo/node_modules" ]
  [ "$(cat "$external/keep.txt")" = 'owner data' ]
}

@test "retirement archive restores branch local commits index dirty files ignored data and symlinks" {
  local repo="$TEST_TMP_DIR/projects/app" archive="$TEST_TMP_DIR/archives" restored="$TEST_TMP_DIR/restored"
  local before_status before_index before_head before_stash
  new_repo "$repo"
  git -C "$repo" checkout -qb local-work
  put_file "$repo/local-only.txt" 'local commit'
  git -C "$repo" add local-only.txt
  git -C "$repo" commit -qm 'unpublished local work'
  put_file "$repo/stashed-note.txt" 'untracked saved work'
  git -C "$repo" stash push -qu -m 'saved untracked note'
  printf 'staged revision\n' > "$repo/README.md"
  git -C "$repo" add README.md
  printf 'unstaged revision\n' >> "$repo/README.md"
  rm "$repo/delete-me.txt"
  put_file "$repo/staged-new.txt" 'new staged file'
  git -C "$repo" add staged-new.txt
  put_file "$repo/notes/untracked.txt" 'untracked work'
  ln -s notes/untracked.txt "$repo/note-link"
  put_file "$repo/.env" 'ignored configuration'
  put_file "$repo/data/records.sqlite" 'ignored user records'
  put_file "$repo/.build/build.log" 'retained build evidence'
  ignored_cache "$repo"
  put_file "$TEST_TMP_DIR/reports/review.txt" 'report outside checkout'
  before_status="$(git -C "$repo" status --porcelain=v1 -uall)"
  before_index="$(git -C "$repo" ls-files --stage)"
  before_head="$(git -C "$repo" rev-parse HEAD)"
  before_stash="$(git -C "$repo" stash list --format='%H %gs')"
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_success
  [ ! -e "$repo" ]
  [ -f "$TEST_TMP_DIR/reports/review.txt" ]
  restore_archive "$archive" "$restored"
  [ "$(git -C "$restored" status --porcelain=v1 -uall)" = "$before_status" ]
  [ "$(git -C "$restored" ls-files --stage)" = "$before_index" ]
  [ "$(git -C "$restored" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$restored" stash list --format='%H %gs')" = "$before_stash" ]
  [ "$(git -C "$restored" show 'stash@{0}^3:stashed-note.txt')" = 'untracked saved work' ]
  [ "$(git -C "$restored" branch --show-current)" = local-work ]
  [ "$(cat "$restored/local-only.txt")" = 'local commit' ]
  [ "$(cat "$restored/README.md")" = "$(printf 'staged revision\nunstaged revision')" ]
  [ "$(cat "$restored/notes/untracked.txt")" = 'untracked work' ]
  [ "$(cat "$restored/.env")" = 'ignored configuration' ]
  [ "$(cat "$restored/data/records.sqlite")" = 'ignored user records' ]
  [ "$(readlink "$restored/note-link")" = notes/untracked.txt ]
  [ -f "$restored/.build/build.log" ]
  [ ! -e "$restored/node_modules" ]
  run git -C "$restored" fsck --no-reflogs
  assert_success
}

@test "retirement discovers first Git roots recursively and leaves surrounding reports intact" {
  local collection="$TEST_TMP_DIR/projects/previews" archive="$TEST_TMP_DIR/archives"
  new_repo "$collection/web/first"
  new_repo "$collection/native/second"
  put_file "$collection/reports/summary.json" '{"retain":true}'
  run "$SCRIPT" --execute --retire-checkouts "$collection" --archive-root "$archive" --no-input
  assert_success
  [ ! -e "$collection/web/first" ]
  [ ! -e "$collection/native/second" ]
  [ -f "$collection/reports/summary.json" ]
  [ "$(find "$archive" -type f -name '*.tar.gz' | wc -l | tr -d ' ')" -eq 2 ]
}

@test "retirement of an existing empty discovery container succeeds without creating an archive" {
  local collection="$TEST_TMP_DIR/projects/empty" archive="$TEST_TMP_DIR/archive"
  mkdir -p "$collection"
  put_file "$collection/reports/summary.txt" 'retain surrounding report'
  run "$SCRIPT" --execute --retire-checkouts "$collection" --archive-root "$archive" --no-input
  assert_success
  [ -f "$collection/reports/summary.txt" ]
  [ ! -e "$archive" ]
}

@test "invalid and conflicting project flags refuse before deleting any selected cache" {
  local repo="$TEST_TMP_DIR/projects/app"
  new_repo "$repo"
  ignored_cache "$repo"
  run "$SCRIPT" --execute --project-caches "$repo" --all --no-input
  assert_refused
  run "$SCRIPT" --execute --project-caches "$repo" --target selenium --no-input
  assert_refused
  run "$SCRIPT" --execute --project-caches "$repo" --retire-checkouts "$repo" --archive-root "$TEST_TMP_DIR/archive" --no-input
  assert_refused
  run "$SCRIPT" --execute --dry-run --project-caches "$repo" --no-input
  assert_refused
  run "$SCRIPT" --execute --retire-checkouts "$repo" --no-input
  assert_refused
  run "$SCRIPT" --execute --project-caches "$repo" --project-caches --no-input
  assert_refused
  [ -f "$repo/node_modules/package/index.js" ]
  [ -f "$repo/README.md" ]
  [ ! -e "$TEST_TMP_DIR/archive" ]
}

@test "project scopes reject global reporting chooser and archive-only option combinations" {
  local repo="$TEST_TMP_DIR/projects/app" archive="$TEST_TMP_DIR/archive"
  new_repo "$repo"
  ignored_cache "$repo"
  run "$SCRIPT" --project-caches "$repo" --list
  assert_refused
  run "$SCRIPT" --project-caches "$repo" --report
  assert_refused
  run "$SCRIPT" --project-caches "$repo" --interactive
  assert_refused
  run "$SCRIPT" --execute --project-caches "$repo" --archive-root "$archive" --no-input
  assert_refused
  run "$SCRIPT" --execute --archive-root "$archive" --no-input
  assert_refused
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root --no-input
  assert_refused
  [ ! -e "$archive" ]
  [ -f "$repo/node_modules/package/index.js" ]
  [ -d "$repo/.git" ]
}

@test "dangerous project roots and relative roots refuse before mutation" {
  put_file "$HOME/keep.txt" 'home remains intact'
  run "$SCRIPT" --execute --project-caches / --no-input
  assert_refused
  run "$SCRIPT" --execute --project-caches "$HOME" --no-input
  assert_refused
  run "$SCRIPT" --execute --project-caches relative-path --no-input
  assert_refused
  [ -f "$HOME/keep.txt" ]
}

@test "symlinked selected roots and overlapping roots refuse all selected cache deletion" {
  local repo="$TEST_TMP_DIR/projects/app"
  new_repo "$repo"
  ignored_cache "$repo"
  ln -s "$repo" "$TEST_TMP_DIR/linked-project"
  run "$SCRIPT" --execute --project-caches "$repo" --project-caches "$TEST_TMP_DIR/linked-project" --no-input
  assert_refused
  [ -f "$repo/node_modules/package/index.js" ]
  run "$SCRIPT" --execute --project-caches "$TEST_TMP_DIR/projects" --project-caches "$repo" --no-input
  assert_refused
  [ -f "$repo/node_modules/package/index.js" ]
}

@test "archive destination inside a retiring checkout or through a symlink is refused" {
  local repo="$TEST_TMP_DIR/projects/app"
  new_repo "$repo"
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$repo/archive" --no-input
  assert_refused
  [ ! -e "$repo/archive" ]
  mkdir -p "$TEST_TMP_DIR/archive-real"
  ln -s "$TEST_TMP_DIR/archive-real" "$TEST_TMP_DIR/archive-link"
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$TEST_TMP_DIR/archive-link" --no-input
  assert_refused
  [ -f "$repo/README.md" ]
  [ -d "$repo/.git" ]
}

@test "retirement refuses linked worktrees and main checkout with external registered worktrees" {
  local repo="$TEST_TMP_DIR/projects/app" linked="$TEST_TMP_DIR/linked"
  new_repo "$repo"
  git -C "$repo" worktree add -q -b preview "$linked"
  run "$SCRIPT" --execute --retire-checkouts "$linked" --archive-root "$TEST_TMP_DIR/archive" --no-input
  assert_refused
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$TEST_TMP_DIR/archive" --no-input
  assert_refused
  [ -f "$repo/README.md" ]
  [ -f "$linked/README.md" ]
  [ -f "$linked/.git" ]
}

@test "retirement refuses an external Git object store instead of archiving incomplete history" {
  local source="$TEST_TMP_DIR/projects/source" shared="$TEST_TMP_DIR/shared"
  new_repo "$source"
  git clone -q --shared "$source" "$shared"
  [ -s "$shared/.git/objects/info/alternates" ]
  run "$SCRIPT" --execute --retire-checkouts "$shared" --archive-root "$TEST_TMP_DIR/archive" --no-input
  assert_refused
  [ -d "$shared/.git" ]
  [ -f "$shared/README.md" ]
  [ -f "$source/README.md" ]
}

@test "retirement refuses absolute core worktree metadata that would bind recovery to the deleted source" {
  local repo="$TEST_TMP_DIR/projects/app" archive="$TEST_TMP_DIR/archive"
  new_repo "$repo"
  git -C "$repo" config core.worktree "$repo"
  [ "$(git -C "$repo" rev-parse --show-toplevel)" = "$repo" ]
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_refused
  [ -f "$repo/README.md" ]
  [ -d "$repo/.git" ]
  [ ! -e "$archive" ]
}

@test "retirement refuses a retained nested shared clone with an external object store" {
  local repo="$TEST_TMP_DIR/projects/app" donor="$TEST_TMP_DIR/donor" archive="$TEST_TMP_DIR/archive"
  local nested
  new_repo "$repo"
  new_repo "$donor"
  nested="$repo/node_modules/shared-dependency"
  git clone -q --shared "$donor" "$nested"
  [ -s "$nested/.git/objects/info/alternates" ]
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_refused
  [ -f "$repo/README.md" ]
  [ -f "$nested/README.md" ]
  [ -f "$donor/README.md" ]
  [ -d "$nested/.git" ]
  [ ! -e "$archive" ]
}

@test "retirement recovery resolves a nested clone relative to its retained internal bare object store" {
  local repo="$TEST_TMP_DIR/projects/app" donor_source="$TEST_TMP_DIR/donor-source"
  local donor nested archive="$TEST_TMP_DIR/archive" restored="$TEST_TMP_DIR/restored" relative before_status
  new_repo "$repo"
  new_repo "$donor_source"
  donor="$repo/object-store.git"
  nested="$repo/deps/nested"
  git clone -q --bare "$donor_source" "$donor"
  git clone -q --shared "$donor" "$nested"
  relative="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$donor/objects" "$nested/.git/objects")"
  printf '%s\n' "$relative" > "$nested/.git/objects/info/alternates"
  printf 'nested local edit\n' >> "$nested/README.md"
  before_status="$(git -C "$nested" status --porcelain=v1 -uall)"
  run git -C "$nested" fsck --no-reflogs
  assert_success
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_success
  [ ! -e "$repo" ]
  restore_archive "$archive" "$restored"
  [ "$(git -C "$restored/deps/nested" status --porcelain=v1 -uall)" = "$before_status" ]
  [ "$(git -C "$restored/deps/nested" log -1 --format=%s)" = initial ]
  run git -C "$restored/deps/nested" fsck --no-reflogs
  assert_success
}

@test "retirement refuses an absolute nested gitdir pointer even when the store is inside the source" {
  local repo="$TEST_TMP_DIR/projects/app" nested archive="$TEST_TMP_DIR/archive" metadata
  new_repo "$repo"
  nested="$repo/deps/nested"
  new_repo "$nested"
  metadata="$repo/git-storage/nested.git"
  mkdir -p "$(dirname "$metadata")"
  mv "$nested/.git" "$metadata"
  printf 'gitdir: %s\n' "$metadata" > "$nested/.git"
  run git -C "$nested" status --porcelain=v1 -uall
  assert_success
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_refused
  [ -f "$repo/README.md" ]
  [ -f "$nested/.git" ]
  [ -f "$nested/README.md" ]
  [ -f "$metadata/HEAD" ]
  [ ! -e "$archive" ]
}

@test "a relative internal alternate whose bare donor depends on external objects is refused" {
  local repo="$TEST_TMP_DIR/projects/app" external="$TEST_TMP_DIR/external"
  local donor nested archive="$TEST_TMP_DIR/archive" relative
  new_repo "$repo"
  new_repo "$external"
  donor="$repo/object-store.git"
  nested="$repo/deps/nested"
  git clone -q --shared --bare "$external" "$donor"
  git clone -q --shared "$donor" "$nested"
  relative="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$donor/objects" "$nested/.git/objects")"
  printf '%s\n' "$relative" > "$nested/.git/objects/info/alternates"
  run git -C "$nested" fsck --no-reflogs
  assert_success
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_refused
  [ -f "$repo/README.md" ]
  [ -f "$nested/README.md" ]
  [ -f "$external/README.md" ]
  [ ! -e "$archive" ]
}

@test "Git failure refuses the project batch without deleting an earlier valid cache" {
  local first="$TEST_TMP_DIR/projects/first" second="$TEST_TMP_DIR/projects/second"
  new_repo "$first"
  new_repo "$second"
  ignored_cache "$first"
  ignored_cache "$second"
  mkdir -p "$TEST_TMP_DIR/bin"
  cat > "$TEST_TMP_DIR/bin/git" <<'STUB'
#!/bin/sh
case "$*" in *"/second"*) echo 'fixture Git failure' >&2; exit 47 ;; esac
exec "$REAL_GIT_BIN" "$@"
STUB
  chmod +x "$TEST_TMP_DIR/bin/git"
  run env PATH="$TEST_TMP_DIR/bin:$PATH" REAL_GIT_BIN="$GIT_BIN" "$SCRIPT" --execute --project-caches "$first" --project-caches "$second" --no-input
  assert_refused
  [ -f "$first/node_modules/package/index.js" ]
  [ -f "$second/node_modules/package/index.js" ]
}

@test "an unwritable archive destination leaves the entire original checkout intact" {
  local repo="$TEST_TMP_DIR/projects/app" archive="$TEST_TMP_DIR/archive"
  new_repo "$repo"
  put_file "$repo/local-note.txt" 'retain work after archive failure'
  mkdir -p "$archive"
  chmod 500 "$archive"
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  chmod 700 "$archive"
  assert_refused
  [ -d "$repo/.git" ]
  [ "$(cat "$repo/local-note.txt")" = 'retain work after archive failure' ]
  [ -f "$repo/README.md" ]
}

@test "retirement refuses a nested relative worktree hidden inside an excluded ignored cache" {
  local repo="$TEST_TMP_DIR/projects/app" nested work archive="$TEST_TMP_DIR/archive" before_status
  new_repo "$repo"
  nested="$repo/nested"
  work="$repo/node_modules/work"
  new_repo "$nested"
  mkdir -p "$work"
  cp "$nested/README.md" "$nested/delete-me.txt" "$nested/.gitignore" "$work/"
  git -C "$nested" config core.worktree ../../node_modules/work
  printf 'uncommitted worktree edit\n' >> "$work/README.md"
  put_file "$work/local-note.txt" 'untracked nested worktree note'
  [ ! -e "$work/.git" ]
  [ "$(git -C "$nested" rev-parse --show-toplevel)" = "$work" ]
  before_status="$(git -C "$nested" status --porcelain=v1 -uall)"
  [[ "$before_status" == *" M README.md"* ]]
  [[ "$before_status" == *"?? local-note.txt"* ]]
  run "$SCRIPT" --execute --retire-checkouts "$repo" --archive-root "$archive" --no-input
  assert_refused
  [ ! -e "$archive" ]
  [ -d "$nested/.git" ]
  [ -f "$repo/README.md" ]
  grep -q 'uncommitted worktree edit' "$work/README.md"
  [ "$(cat "$work/local-note.txt")" = 'untracked nested worktree note' ]
  [ "$(git -C "$nested" status --porcelain=v1 -uall)" = "$before_status" ]
}
