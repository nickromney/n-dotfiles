#!/usr/bin/env bash
# Detach legacy folded runtime directories without deleting their source state.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/migrate-runtime-roots.sh [--dry-run|--execute] [aws|gh|nushell|ssh ...]

Replace runtime directory symlinks into this checkout with private local copies.
Default: preview all four packages. Never prompts or changes Git state.
Backups are kept in ~/.n-dotfiles-runtime-backups; source files are retained.
Close programs using these directories before executing the migration.

Options:
  --dry-run   Show affected directories without changing files (default)
  --execute   Copy, verify, back up, and detach each recognized directory link
  -h, --help  Show this help message

Examples:
  scripts/migrate-runtime-roots.sh --dry-run
  scripts/migrate-runtime-roots.sh --execute aws gh nushell
EOF
}

mode=--dry-run
packages=()
for arg in "$@"; do
  case "$arg" in
    --dry-run | --execute) mode=$arg ;;
    -h | --help) usage; exit 0 ;;
    aws | gh | nushell | ssh) packages+=("$arg") ;;
    *) echo "Error: unknown option or package: $arg" >&2; exit 1 ;;
  esac
done
[[ ${#packages[@]} -gt 0 ]] || packages=(aws gh nushell ssh)
command -v python3 >/dev/null 2>&1 || { echo 'Error: python3 is required' >&2; exit 1; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" "$mode" "${packages[@]}" <<'PY'
import hashlib
import os
from pathlib import Path
import shutil
import sys
import tempfile

repo = Path(sys.argv[1]).resolve()
execute = sys.argv[2] == '--execute'
user_home = Path(os.environ['HOME'])
layouts = {
    'aws': ('.aws', ['aws-1password']),
    'gh': ('.config/gh', ['config.yml']),
    'nushell': ('Library/Application Support/nushell', [
        'config.nu', 'env.nu', 'vendor/autoload/kubectl.nu',
        'vendor/autoload/mise.nu', 'vendor/autoload/starship.nu',
        'vendor/autoload/uv-completions.nu']),
    'ssh': ('.ssh', []),
}

def fingerprint(directory):
    entries = {}
    for path in directory.rglob('*'):
        relative = str(path.relative_to(directory))
        if path.is_symlink():
            entries[relative] = ('link', os.readlink(path))
        elif path.is_file():
            entries[relative] = ('file', hashlib.sha256(path.read_bytes()).hexdigest())
        elif path.is_dir():
            entries[relative] = ('directory',)
        else:
            raise RuntimeError('Runtime root contains a special file; migration stopped')
    return entries

try:
    plans = []
    for package in dict.fromkeys(sys.argv[3:]):
        relative, managed = layouts[package]
        target = user_home / relative
        source = repo / package / relative
        if not source.is_dir() or not target.exists() or target.resolve() != source.resolve():
            print(f'{package}: already machine-local or absent')
            continue
        if not target.is_symlink() or repo in target.parent.resolve().parents or target.parent.resolve() == repo:
            raise RuntimeError(f'{package}: an ancestor is folded into the repo; migrate that link manually')
        for path in source.rglob('*'):
            if path.is_symlink() and not os.path.isabs(os.readlink(path)):
                raise RuntimeError(f'{package}: a relative symlink needs manual rebasing before migration')
            if path.is_symlink() and (path.resolve() == source or source in path.resolve().parents):
                raise RuntimeError(f'{package}: an internal runtime symlink needs manual migration')
        plans.append((package, target, source, managed, os.readlink(target)))
        print(f'{package}: would copy, verify, back up, and detach {target}')
    if not execute or not plans:
        sys.exit(0)

    backup_base = user_home / '.n-dotfiles-runtime-backups'
    if backup_base.is_symlink() or backup_base.resolve() == repo or repo in backup_base.resolve().parents:
        raise RuntimeError('Backup directory must be a real machine-local directory')
    backup_base.mkdir(mode=0o700, exist_ok=True)
    backup_base.chmod(0o700)
    batch = Path(tempfile.mkdtemp(prefix='migration-', dir=backup_base))
    for package, target, source, managed, old_link in plans:
        original = fingerprint(source)
        backup = batch / package
        backup.mkdir(mode=0o700)
        shutil.copytree(source, backup / 'files', symlinks=True)
        (backup / 'original-link.txt').write_text(old_link + '\n')
        stage = Path(tempfile.mkdtemp(prefix=f'.{target.name}.migrate-', dir=target.parent))
        try:
            # Keep the staging root private throughout copying; copytree would
            # otherwise copy the public source directory's mode onto that root.
            for item in source.iterdir():
                copy = stage / item.name
                if item.is_symlink():
                    copy.symlink_to(os.readlink(item))
                elif item.is_dir():
                    shutil.copytree(item, copy, symlinks=True)
                else:
                    shutil.copy2(item, copy)
            if fingerprint(backup / 'files') != original or fingerprint(stage) != original or fingerprint(source) != original:
                raise RuntimeError(f'{package}: contents changed while copying; active link was preserved')
            for relative in managed:
                portable = source / relative
                copy = stage / relative
                if portable.is_file():
                    copy.unlink()
                    # Stow recognizes its relative package links on subsequent
                    # runs. Calculate against the final destination, not stage.
                    final_root = target.parent.resolve() / target.name
                    final_parent = (final_root / relative).parent
                    copy.symlink_to(os.path.relpath(portable.resolve(), final_parent))
            stage.chmod(0o700)
            if not target.is_symlink() or os.readlink(target) != old_link or target.resolve() != source.resolve():
                raise RuntimeError(f'{package}: active link changed while copying; migration stopped')
            target.unlink()
            try:
                stage.rename(target)
            except BaseException:
                target.symlink_to(old_link)
                raise
        finally:
            if stage.exists():
                shutil.rmtree(stage)
        print(f'{package}: migrated; backup: {backup}')
except (OSError, RuntimeError) as error:
    print(f'Error: {error}', file=sys.stderr)
    sys.exit(1)
PY
