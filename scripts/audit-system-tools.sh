#!/usr/bin/env bash
# Report-only inventory of installed tools, PATH surfaces, applications, and
# curated overlap candidates. This script never removes or changes anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${AUDIT_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUT_DIR="${AUDIT_OUT_DIR:-}"
PATH_VALUE="${AUDIT_PATH:-$PATH}"
APPLICATION_ROOTS="${AUDIT_APPLICATION_ROOTS:-/Applications:$HOME/Applications:/System/Applications}"
BREW_CMD="${AUDIT_BREW_CMD:-brew}"
MISE_CMD="${AUDIT_MISE_CMD:-mise}"

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/audit-system-tools.sh [options]

Create a report-only inventory of Homebrew, mise, PATH entries, applications,
and likely overlapping command-line tools. Findings are candidates for review;
the script does not uninstall, clean, or modify the machine.

Options:
  -h, --help                 Show this help message
  -o, --out-dir <path>       Write the report to this directory
      --path <value>         Audit this PATH instead of the current PATH
      --applications <value> Colon-separated application roots to scan

Environment overrides (useful for tests):
  AUDIT_REPO_ROOT, AUDIT_OUT_DIR, AUDIT_PATH, AUDIT_APPLICATION_ROOTS
  AUDIT_BREW_CMD, AUDIT_MISE_CMD

Examples:
  scripts/audit-system-tools.sh
  scripts/audit-system-tools.sh --out-dir /tmp/n-dotfiles-system-audit
  scripts/audit-system-tools.sh --path "$PATH"

Report files:
  summary.md                  Executive summary and interpretation notes
  brew-leaf-candidates.tsv    Unmanaged top-level formulae to review
  brew-cask-candidates.tsv    Installed casks absent from the Brewfile
  brew-declared-missing.tsv   Declared Brewfile entries missing locally
  brew-mise-overlap.tsv       Formulae installed by both Homebrew and mise
  mise-status.txt             Raw mise status output
  path-directories.tsv        PATH entries, existence, and source class
  path-executables.tsv        Executables found in each PATH directory
  path-shadowing.tsv          Commands provided by multiple PATH directories
  applications.tsv            .app bundles, bundle IDs, and last-used dates
  overlap-candidates.tsv      Curated groups with two or more installed tools
EOF

  exit "$exit_code"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage 0
      ;;
    -o | --out-dir)
      [[ -n "${2:-}" ]] || die "$1 requires a path"
      OUT_DIR="$2"
      shift 2
      ;;
    --path)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      PATH_VALUE="$2"
      shift 2
      ;;
    --applications)
      [[ -n "${2:-}" ]] || die "$1 requires a colon-separated path list"
      APPLICATION_ROOTS="$2"
      shift 2
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

[[ -f "$REPO_ROOT/Brewfile" ]] || die "Brewfile not found under $REPO_ROOT"
[[ -f "$REPO_ROOT/mise/.config/mise/config.toml" ]] || die "mise config not found under $REPO_ROOT"

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="${TMPDIR:-/tmp}/n-dotfiles-system-audit-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUT_DIR"

command_available() {
  command -v "$1" >/dev/null 2>&1
}

classify_path() {
  case "$1" in
    "${HOME}/.local/share/mise/shims" | "${HOME}/.local/share/mise/bin" | "${HOME}/.local/share/mise/installs/"*) echo "mise" ;;
    "${HOME}/.cargo/bin") echo "cargo" ;;
    "${HOME}/.local/bin") echo "user-local" ;;
    /opt/homebrew/bin | /opt/homebrew/sbin | /usr/local/bin | /home/linuxbrew/.linuxbrew/bin) echo "homebrew" ;;
    /usr/bin | /bin | /usr/sbin | /sbin) echo "system" ;;
    *) echo "other" ;;
  esac
}

manifest_formulae() {
  awk -F'"' '/^[[:space:]]*brew[[:space:]]+"/{name=$2; sub(/^.*\//, "", name); print name}' \
    "$REPO_ROOT/Brewfile" | sort -u
}

manifest_casks() {
  {
    awk -F'"' '/^[[:space:]]*cask[[:space:]]+"/{print $2}' "$REPO_ROOT/Brewfile"
    if grep -qE '^[[:space:]]*cask[[:space:]]+jetbrains_ide' "$REPO_ROOT/Brewfile"; then
      printf '%s\n' "${JETBRAINSIDE:-RubyMine}" | tr '[:upper:]' '[:lower:]'
    fi
  } | sed 's|.*/||' | sort -u
}

write_brew_reports() {
  local declared_formulae declared_casks installed_formulae installed_casks leaves
  local brew_error="$OUT_DIR/brew-errors.txt"
  : >"$brew_error"
  printf 'kind\tname\treason\n' >"$OUT_DIR/brew-leaf-candidates.tsv"
  printf 'kind\tname\treason\n' >"$OUT_DIR/brew-cask-candidates.tsv"
  printf 'kind\tname\treason\n' >"$OUT_DIR/brew-declared-missing.tsv"

  declared_formulae="$(manifest_formulae)"
  declared_casks="$(manifest_casks)"

  if ! command_available "$BREW_CMD"; then
    printf 'brew not found on PATH\n' >"$OUT_DIR/brew-status.txt"
    return 0
  fi

  if ! installed_formulae="$("$BREW_CMD" list --formula 2>>"$brew_error")"; then
    printf 'brew formula inventory failed\n' >>"$OUT_DIR/brew-status.txt"
    installed_formulae=""
  fi
  if ! installed_casks="$("$BREW_CMD" list --cask 2>>"$brew_error")"; then
    printf 'brew cask inventory failed\n' >>"$OUT_DIR/brew-status.txt"
    installed_casks=""
  fi
  if ! leaves="$("$BREW_CMD" leaves 2>>"$brew_error")"; then
    printf 'brew leaf inventory failed\n' >>"$OUT_DIR/brew-status.txt"
    leaves=""
  fi

  printf '%s\n' "$installed_formulae" | sed '/^$/d; s|.*/||' | sort -u >"$OUT_DIR/brew-formulae-installed.txt"
  printf '%s\n' "$installed_casks" | sed '/^$/d; s|.*/||' | sort -u >"$OUT_DIR/brew-casks-installed.txt"
  printf '%s\n' "$leaves" | sed '/^$/d; s|.*/||' | sort -u >"$OUT_DIR/brew-leaves.txt"
  printf '%s\n' "$declared_formulae" | sed '/^$/d' >"$OUT_DIR/brew-formulae-declared.txt"
  printf '%s\n' "$declared_casks" | sed '/^$/d' >"$OUT_DIR/brew-casks-declared.txt"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if ! grep -Fqx "$name" "$OUT_DIR/brew-formulae-declared.txt"; then
      printf 'formula\t%s\tunmanaged top-level formula (review before brew uninstall)\n' "$name" >>"$OUT_DIR/brew-leaf-candidates.tsv"
    fi
  done <"$OUT_DIR/brew-leaves.txt"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if ! grep -Fqx "$name" "$OUT_DIR/brew-casks-declared.txt"; then
      printf 'cask\t%s\tinstalled cask absent from Brewfile\n' "$name" >>"$OUT_DIR/brew-cask-candidates.tsv"
    fi
  done <"$OUT_DIR/brew-casks-installed.txt"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if ! grep -Fqx "$name" "$OUT_DIR/brew-formulae-installed.txt"; then
      printf 'formula\t%s\tdeclared formula missing locally\n' "$name" >>"$OUT_DIR/brew-declared-missing.tsv"
    fi
  done <"$OUT_DIR/brew-formulae-declared.txt"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if ! grep -Fqx "$name" "$OUT_DIR/brew-casks-installed.txt"; then
      printf 'cask\t%s\tdeclared cask missing locally\n' "$name" >>"$OUT_DIR/brew-declared-missing.tsv"
    fi
  done <"$OUT_DIR/brew-casks-declared.txt"

  if [[ -s "$brew_error" ]]; then
    printf 'brew reported errors; see brew-errors.txt\n' >>"$OUT_DIR/brew-status.txt"
  else
    printf 'brew inventories completed successfully\n' >"$OUT_DIR/brew-status.txt"
  fi
}

write_mise_report() {
  if command_available "$MISE_CMD"; then
    "$MISE_CMD" ls >"$OUT_DIR/mise-status.txt" 2>&1 || true
  else
    printf 'mise not found on PATH\n' >"$OUT_DIR/mise-status.txt"
  fi
}

write_brew_mise_overlap() {
  local mise_tool brew_formula
  printf 'brew_formula\tmise_tool\treason\n' >"$OUT_DIR/brew-mise-overlap.tsv"
  if [[ ! -s "$OUT_DIR/brew-formulae-installed.txt" ]]; then
    return 0
  fi

  awk -F'=' '
    /^[[:space:]]*\[tools\][[:space:]]*$/ {in_tools=1; next}
    /^[[:space:]]*\[/ {in_tools=0}
    in_tools && /=/ {
      key=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^"|"$/, "", key)
      sub(/^.*\//, "", key)
      print key
    }
  ' "$REPO_ROOT/mise/.config/mise/config.toml" | sort -u >"$OUT_DIR/mise-tool-names.txt"

  while IFS= read -r brew_formula; do
    [[ -n "$brew_formula" ]] || continue
    if grep -Fqx "$brew_formula" "$OUT_DIR/mise-tool-names.txt"; then
      mise_tool="$brew_formula"
      printf '%s\t%s\tSame tool appears in both package-manager surfaces; prefer one owner\n' \
        "$brew_formula" "$mise_tool" >>"$OUT_DIR/brew-mise-overlap.tsv"
    fi
  done <"$OUT_DIR/brew-formulae-installed.txt"
}

write_path_reports() {
  local path_dir index=0 candidate name source
  printf 'index\tdirectory\texists\tclass\n' >"$OUT_DIR/path-directories.tsv"
  printf 'directory\tcommand\tclass\n' >"$OUT_DIR/path-executables.tsv"

  while IFS= read -r path_dir; do
    source="$(classify_path "$path_dir")"
    if [[ -d "$path_dir" ]]; then
      printf '%s\t%s\tyes\t%s\n' "$index" "$path_dir" "$source" >>"$OUT_DIR/path-directories.tsv"
      for candidate in "$path_dir"/*; do
        if [[ -f "$candidate" || -L "$candidate" ]] && [[ -x "$candidate" ]]; then
          name="${candidate##*/}"
          printf '%s\t%s\t%s\n' "$path_dir" "$name" "$source" >>"$OUT_DIR/path-executables.tsv"
        fi
      done
    else
      printf '%s\t%s\tno\t%s\n' "$index" "$path_dir" "$source" >>"$OUT_DIR/path-directories.tsv"
    fi
    index=$((index + 1))
  done < <(printf '%s' "$PATH_VALUE" | awk -v RS=: '{print}')

  {
    printf 'command\tproviders\tlocations\n'
    tail -n +2 "$OUT_DIR/path-executables.tsv" | awk -F'\t' '{loc[$2]=loc[$2] (loc[$2] ? "," : "") $1; count[$2]++} END {for (name in count) if (count[name] > 1) printf "%s\t%d\t%s\n", name, count[name], loc[name]}' | sort
  } >"$OUT_DIR/path-shadowing.tsv"
}

write_applications_report() {
  local root app bundle_id last_used
  printf 'root\tapplication\tbundle_id\tlast_used\n' >"$OUT_DIR/applications.tsv"
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    while IFS= read -r app; do
      bundle_id="unavailable"
      last_used="unavailable"
      if command_available mdls; then
        bundle_id="$(mdls -raw -name kMDItemCFBundleIdentifier "$app" 2>/dev/null || true)"
        last_used="$(mdls -raw -name kMDItemLastUsedDate "$app" 2>/dev/null || true)"
        case "$bundle_id" in
          "" | *"could not find"*) bundle_id="unavailable" ;;
        esac
        case "$last_used" in
          "" | *"could not find"*) last_used="unavailable" ;;
        esac
      fi
      printf '%s\t%s\t%s\t%s\n' "$root" "$app" "$bundle_id" "$last_used" >>"$OUT_DIR/applications.tsv"
    done < <(find "$root" -maxdepth 1 -type d -name '*.app' -print 2>/dev/null | sort)
  done < <(printf '%s' "$APPLICATION_ROOTS" | awk -v RS=: '{print}')
}

write_overlap_report() {
  local group members note member installed
  printf 'group\tinstalled_members\twhy_review\n' >"$OUT_DIR/overlap-candidates.tsv"
  while IFS='|' read -r group members note; do
    installed=""
    IFS=',' read -ra member_list <<<"$members"
    for member in "${member_list[@]}"; do
      if command_available "$member"; then
        installed="${installed:+$installed,}$member"
      fi
    done
    if [[ "$installed" == *,* ]]; then
      printf '%s\t%s\t%s\n' "$group" "$installed" "$note" >>"$OUT_DIR/overlap-candidates.tsv"
    fi
  done <<'EOF'
listing|ls,eza|eza may cover the daily listing use of ls
file-search|find,fd|fd may cover common filename search use of find
text-search|grep,rg|rg may cover most recursive code search use of grep
file-viewing|cat,bat|bat may cover most human-readable file viewing use of cat
http|curl,httpie,xh,wget|one client may cover the majority of ad-hoc HTTP requests
terminal-file-manager|ranger,yazi|review whether both file managers are needed
git-ui|git,lazygit|lazygit wraps git; review whether its UI is still used
data-query|jq,fx|review whether both JSON/query workflows are active
infrastructure|terraform,tofu|review whether both Terraform-compatible CLIs are needed
system-monitor|top,bpytop|review whether the richer monitor replaces the simpler one
EOF
}

write_summary() {
  local leaves casks missing shadow overlaps apps missing_dirs
  leaves=$(($(wc -l <"$OUT_DIR/brew-leaf-candidates.tsv") - 1))
  casks=$(($(wc -l <"$OUT_DIR/brew-cask-candidates.tsv") - 1))
  missing=$(($(wc -l <"$OUT_DIR/brew-declared-missing.tsv") - 1))
  brew_mise=$(($(wc -l <"$OUT_DIR/brew-mise-overlap.tsv") - 1))
  shadow=$(($(wc -l <"$OUT_DIR/path-shadowing.tsv") - 1))
  overlaps=$(($(wc -l <"$OUT_DIR/overlap-candidates.tsv") - 1))
  apps=$(($(wc -l <"$OUT_DIR/applications.tsv") - 1))
  missing_dirs=$(awk -F'\t' 'NR > 1 && $3 == "no" {count++} END {print count + 0}' "$OUT_DIR/path-directories.tsv")

  cat >"$OUT_DIR/summary.md" <<EOF
# System tools audit

This is a report-only inventory generated on $(date).

## Counts

| Area | Count |
| --- | ---: |
| Unmanaged Homebrew leaves | $leaves |
| Installed casks absent from Brewfile | $casks |
| Declared Brewfile entries missing locally | $missing |
| Formulae installed by both Homebrew and mise | $brew_mise |
| PATH directories missing | $missing_dirs |
| Commands shadowed by multiple PATH directories | $shadow |
| Curated overlap groups with multiple members | $overlaps |
| Application bundles found | $apps |

## How to interpret this

- An unmanaged formula leaf or cask is a removal candidate, not proof that it
  is dead. Check whether it is used by a project, a launch agent, or another
  person on the machine.
- Formula dependencies are deliberately not called dead: removing a leaf can
  make Homebrew remove dependencies that another workflow still needs.
- PATH shadowing means the first matching executable wins. Inspect
  path-shadowing.tsv before deleting or reordering anything.
- Overlap groups are curated 70%-coverage heuristics, not semantic proofs.
  The report intentionally avoids recommending deletion automatically.
- Application inventory is filesystem evidence. Homebrew cask names do not
  always match their .app bundle names, so cask-to-app mapping requires
  manual confirmation.

## Files

See the TSV and raw status files beside this summary for the evidence behind
each count.
EOF
}

echo "Writing system tools audit to $OUT_DIR"
write_brew_reports
write_mise_report
write_brew_mise_overlap
write_path_reports
write_applications_report
write_overlap_report
write_summary
cat "$OUT_DIR/summary.md"
