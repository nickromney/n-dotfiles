#!/usr/bin/env python3
"""Preview or remove ignored project caches; optionally archive and retire checkouts."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile


CACHE_NAMES = {
    "node_modules", ".venv", ".uv-cache", "uv-cache", ".next", ".zig-cache",
    "zig-out", ".pytest_cache", ".ruff_cache", ".mypy_cache", ".gocache",
    ".go-build", ".astro",
}
EVIDENCE_NAMES = {
    "logs", "reports", "evidence", "test-results", "playwright-report",
    ".verify", ".codex-artifacts", ".playwright-mcp", ".playwright-cli",
    "visual-tour", "screenshots",
}
GIT_ENVIRONMENT = {
    "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_INDEX_FILE",
}


def git(root, *args):
    env = {key: value for key, value in os.environ.items() if key not in GIT_ENVIRONMENT}
    env["GIT_OPTIONAL_LOCKS"] = "0"
    result = subprocess.run(
        ["git", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
         "-C", str(root), *args], env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode:
        raise RuntimeError("Git inspection failed for {}: {}".format(
            root, os.fsdecode(result.stderr).strip()))
    return result.stdout


def no_links(path):
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise RuntimeError("Symlinked path or parent: " + str(part))


def checked_path(value, must_exist=True):
    supplied = Path(value).expanduser()
    if not supplied.is_absolute():
        supplied = Path.cwd() / supplied
    no_links(supplied)
    path = Path(os.path.abspath(str(supplied)))
    no_links(path)
    protected = {Path("/"), Path.home()}
    if path in protected or path in Path.home().parents:
        raise RuntimeError("Protected root cannot be selected: " + str(path))
    if path.exists() and not path.is_dir():
        raise RuntimeError("Not a directory: " + str(path))
    if must_exist and not path.is_dir():
        raise RuntimeError("Directory does not exist: " + str(path))
    return path


def check_disjoint(paths, label):
    for index, first in enumerate(paths):
        for second in paths[index + 1:]:
            if first == second or first in second.parents or second in first.parents:
                raise RuntimeError("Duplicate or overlapping {}: {} and {}".format(
                    label, first, second))


def stamp(path):
    info = path.lstat()
    return [info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns,
            info.st_ino, info.st_dev]


def digest(stream):
    result = hashlib.sha256()
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            return result.hexdigest()
        result.update(chunk)


def scan(root, excluded=(), allow_special=False):
    excluded = set(excluded)
    records = {}

    def visit(path):
        relative = path.relative_to(root).as_posix()
        if relative in excluded:
            return
        info = stamp(path)
        mode = info[0]
        row = {"stamp": info}
        if stat.S_ISDIR(mode):
            row["kind"] = "dir"
            records[relative] = row
            for child in sorted(path.iterdir()):
                visit(child)
        elif stat.S_ISREG(mode):
            row["kind"] = "file"
            records[relative] = row
        elif stat.S_ISLNK(mode):
            row.update(kind="link", link=os.readlink(path))
            records[relative] = row
        elif allow_special:
            row["kind"] = "special"
            records[relative] = row
        else:
            raise RuntimeError("Cannot preserve special file: " + str(path))

    visit(root)
    return records


def unchanged(root, original, label):
    no_links(root)
    current = scan(root, allow_special=True)
    if current != original:
        raise RuntimeError("Source changed {}: {}".format(label, root))


def contains_git(path):
    for folder, directories, files in os.walk(path, followlinks=False):
        if ".git" in directories or ".git" in files:
            return True
        if "HEAD" in files and "objects" in directories and "refs" in directories:
            return True
        directories[:] = [name for name in directories
                          if not (Path(folder) / name).is_symlink()]
    return False


def contains_evidence(path, build=False):
    for folder, directories, files in os.walk(path, followlinks=False):
        for name in directories + files:
            lower = name.lower()
            if (lower in EVIDENCE_NAMES or lower.endswith(".xcresult")
                    or lower.endswith((".tfstate", ".tfstate.backup", ".tfplan"))
                    or (build and lower.endswith(".log"))):
                return True
        directories[:] = [name for name in directories
                          if not (Path(folder) / name).is_symlink()]
    return False


def cache_container(parent, name):
    return (name in CACHE_NAMES or name == ".build"
            or (parent.name == ".terraform" and name in {"providers", "modules"})
            or (parent.name == ".cache" and name == "uv"))


def discover_git_roots(root):
    found = []
    for folder, directories, files in os.walk(root, followlinks=False):
        parent = Path(folder)
        marker = parent / ".git"
        if ".git" in directories or ".git" in files:
            if marker.is_symlink():
                raise RuntimeError("Symlinked Git directory: " + str(marker))
            found.append(parent)
        directories[:] = [name for name in directories
                          if name != ".git" and not (parent / name).is_symlink()
                          and not cache_container(parent, name)]
    return sorted(found)


def repository_root(root):
    actual = Path(os.fsdecode(git(root, "rev-parse", "--show-toplevel")).strip())
    if actual != root:
        raise RuntimeError("Git owner differs from selected checkout: " + str(root))
    return actual


def cache_refusal(root, path, build=False):
    if path.is_symlink() or not path.is_dir():
        return "symlink or non-directory"
    relative = path.relative_to(root).as_posix()
    env = {key: value for key, value in os.environ.items() if key not in GIT_ENVIRONMENT}
    env["GIT_OPTIONAL_LOCKS"] = "0"
    ignored = subprocess.run(
        ["git", "-c", "core.fsmonitor=false", "-C", str(root), "check-ignore",
         "-q", "--", relative], env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if ignored.returncode not in (0, 1):
        raise RuntimeError("Git ignore inspection failed for " + str(path))
    if ignored.returncode:
        return "not ignored by its Git owner"
    protected = git(root, "ls-files", "-z", "--cached", "--others",
                    "--exclude-standard", "--", relative)
    if protected:
        return "contains tracked or nonignored untracked files"
    if contains_git(path):
        return "contains a nested Git repository"
    if contains_evidence(path, build=build):
        return "contains retained evidence, build logs or Terraform state"
    return None


def disposable(root, path, build=False):
    return cache_refusal(root, path, build=build) is None


def cache_candidates(root, skipped=None):
    repository_root(root)
    candidates = []
    for folder, directories, _ in os.walk(root, followlinks=False):
        parent = Path(folder)
        for name in list(directories):
            path = parent / name
            if name == ".git" or path.is_symlink():
                if skipped is not None and cache_container(parent, name):
                    skipped.append((path, "symlinked cache path"))
                directories.remove(name)
                continue
            if (path / ".git").exists() or (path / ".git").is_symlink():
                if skipped is not None and cache_container(parent, name):
                    skipped.append((path, "contains a nested Git repository"))
                # Nested source repositories are inspected using their own Git owner.
                directories.remove(name)
                continue
            if name == ".build" or (parent.name == ".terraform" and name == "modules"):
                # Keep direct logs, result bundles, workspace metadata and modules.json.
                for child in sorted(path.iterdir()):
                    if not child.is_dir() or child.is_symlink():
                        continue
                    if (child.name.lower() in EVIDENCE_NAMES
                            or child.name.lower().endswith(".xcresult")):
                        reason = "retained evidence or build logs"
                    else:
                        reason = cache_refusal(root, child, build=name == ".build")
                    if reason is None:
                        candidates.append(child)
                    elif skipped is not None:
                        skipped.append((child, reason))
                directories.remove(name)
            elif cache_container(parent, name):
                reason = cache_refusal(root, path)
                if reason is None:
                    candidates.append(path)
                elif skipped is not None:
                    skipped.append((path, reason))
                # Never descend into a rejected dependency/cache container.
                directories.remove(name)
    return sorted(candidates)


def allocated_kib(path):
    result = subprocess.run(["du", "-skP", str(path)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError("Cannot measure {}: {}".format(path, result.stderr.strip()))
    return int(result.stdout.split()[0])


def cache_plan(roots, skipped=None):
    plan = []
    for requested in roots:
        repositories = discover_git_roots(requested)
        if not repositories:
            raise RuntimeError("No Git checkouts found under " + str(requested))
        for repository in repositories:
            for path in cache_candidates(repository, skipped=skipped):
                no_links(path)
                plan.append({"path": path, "owner": repository,
                             "kib": allocated_kib(path),
                             "snapshot": scan(path, allow_special=True)})
    check_disjoint([row["path"] for row in plan], "cache candidates")
    return plan


def execute_cache_cleanup(plan):
    # Validate the complete plan again before the first deletion.
    owners = {row["owner"] for row in plan}
    fresh_candidates = {owner: set(cache_candidates(owner)) for owner in owners}
    for row in plan:
        unchanged(row["path"], row["snapshot"], "before cache cleanup")
        if row["path"] not in fresh_candidates[row["owner"]]:
            raise RuntimeError("Cache is no longer disposable: " + str(row["path"]))
    for row in plan:
        unchanged(row["path"], row["snapshot"], "before cache deletion")
        if not disposable(row["owner"], row["path"], build=".build" in row["path"].parts):
            raise RuntimeError("Cache is no longer disposable: " + str(row["path"]))
        shutil.rmtree(row["path"])
        print("Removed cache: " + str(row["path"]), flush=True)


def retained_git_path(path, root, excluded):
    no_links(path)
    resolved = path.resolve()
    if not resolved.is_relative_to(root):
        raise RuntimeError("Git storage points outside checkout: " + str(path))
    if any(resolved == root / relative or root / relative in resolved.parents
           for relative in excluded):
        raise RuntimeError("Git storage points into an omitted cache: " + str(path))
    if not resolved.is_dir():
        raise RuntimeError("Missing Git storage directory: " + str(path))
    return resolved


def validate_object_database(objects, root, excluded, visited):
    objects = retained_git_path(objects, root, excluded)
    if objects in visited:
        return
    visited.add(objects)
    for folder, directories, files in os.walk(objects, followlinks=False):
        for name in directories + files:
            if (Path(folder) / name).is_symlink():
                raise RuntimeError("Symlink in Git object database: " + str(Path(folder) / name))
    if (objects / "info/http-alternates").exists():
        raise RuntimeError("HTTP Git alternates cannot be archived: " + str(objects))
    alternate_file = objects / "info/alternates"
    if not alternate_file.exists():
        return
    no_links(alternate_file)
    for line in alternate_file.read_text().splitlines():
        if not line:
            continue
        if line.startswith('"'):
            raise RuntimeError("Quoted Git alternates are unsupported: " + str(alternate_file))
        target = Path(line)
        if target.is_absolute():
            raise RuntimeError("Absolute Git alternates are not relocatable: " + str(alternate_file))
        # Git resolves alternate paths relative to objects/, not objects/info/.
        validate_object_database(objects / target, root, excluded, visited)


def validate_git_storage(root, excluded=()):
    repository_root(root)
    marker = root / ".git"
    if not marker.is_dir() or marker.is_symlink():
        raise RuntimeError("Only standalone checkouts can be retired: " + str(root))
    common = Path(os.fsdecode(git(root, "rev-parse", "--git-common-dir")).strip())
    if not common.is_absolute():
        common = root / common
    if common.resolve() != marker.resolve():
        raise RuntimeError("External Git store cannot be archived: " + str(root))
    if (marker / "worktrees").exists():
        raise RuntimeError("Checkout has registered linked worktrees: " + str(root))
    stores = {marker}
    for folder, directories, files in os.walk(root, followlinks=False):
        parent = Path(folder)
        if ".git" in directories:
            stores.add(parent / ".git")
        if "HEAD" in files and "objects" in directories and "refs" in directories:
            stores.add(parent)
        nested_marker = parent / ".git"
        if parent != root and nested_marker.is_file():
            if nested_marker.is_symlink():
                raise RuntimeError("Symlinked nested Git pointer: " + str(nested_marker))
            content = nested_marker.read_text().strip()
            if not content.startswith("gitdir: "):
                raise RuntimeError("Invalid nested Git pointer: " + str(nested_marker))
            target = Path(content[len("gitdir: "):])
            if target.is_absolute():
                raise RuntimeError("Absolute nested Git pointer is not relocatable: " + str(nested_marker))
            target = retained_git_path(parent / target, root, excluded)
            stores.add(target)
        directories[:] = [name for name in directories
                          if not (parent / name).is_symlink()]
    object_databases = set()
    for store in sorted(stores):
        no_links(store)
        if not store.is_dir():
            raise RuntimeError("Missing Git storage: " + str(store))
        if (store / "worktrees").exists():
            raise RuntimeError("Git storage has registered linked worktrees: " + str(store))
        validate_object_database(store / "objects", root, excluded, object_databases)
        for folder, directories, files in os.walk(store, followlinks=False):
            for name in directories + files:
                if (Path(folder) / name).is_symlink():
                    raise RuntimeError("Symlink in Git storage: " + str(Path(folder) / name))
        storage_common = Path(os.fsdecode(git(
            root, "--git-dir=" + str(store), "rev-parse", "--git-common-dir")).strip())
        if not storage_common.is_absolute():
            storage_common = root / storage_common
        if storage_common.resolve() != store.resolve():
            raise RuntimeError("Git storage uses another common directory: " + str(store))
        env = {key: value for key, value in os.environ.items() if key not in GIT_ENVIRONMENT}
        env["GIT_OPTIONAL_LOCKS"] = "0"
        worktree = subprocess.run(
            ["git", "--git-dir=" + str(store), "config", "--get", "core.worktree"],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if worktree.returncode not in (0, 1):
            raise RuntimeError("Cannot inspect Git worktree configuration: " + str(store))
        if worktree.returncode == 0:
            value = Path(os.fsdecode(worktree.stdout).strip())
            if value.is_absolute() or not (store / value).resolve().is_relative_to(root):
                raise RuntimeError("Git core.worktree is not relocatable within archive: " + str(store))
            retained_git_path(store / value, root, excluded)


def inspect_checkout(root):
    no_links(root)
    excluded = [path.relative_to(root).as_posix() for path in cache_candidates(root)]
    validate_git_storage(root, excluded)
    return {"path": str(root), "head": os.fsdecode(git(root, "rev-parse", "HEAD")).strip(),
            "status": os.fsdecode(git(root, "status", "--porcelain=v1", "--untracked-files=all")),
            "allocated_kib": allocated_kib(root), "excluded_caches": excluded,
            "entries": scan(root, excluded), "snapshot": scan(root, allow_special=True)}


def archive_paths(root, destination):
    name = root.parent.name + "--" + root.name
    return (destination / (name + ".tar.gz"), destination / (name + ".json"),
            destination / (name + ".tar.gz.partial"))


def retirement_plan(roots, destination):
    checkouts = []
    for requested in roots:
        discovered = discover_git_roots(requested)
        # An outer archive preserves nested source repositories and their Git data.
        checkouts.extend(path for path in discovered
                         if not any(other in path.parents for other in discovered))
    check_disjoint(checkouts, "checkout selections")
    paths = []
    for root in checkouts:
        if destination == root or destination in root.parents or root in destination.parents:
            raise RuntimeError("Archive root overlaps a checkout: " + str(root))
        for path in archive_paths(root, destination):
            if path.exists() or path.is_symlink():
                raise RuntimeError("Recovery destination already exists: " + str(path))
            if path in paths:
                raise RuntimeError("Recovery destination collision: " + str(path))
            paths.append(path)
    # Every Git/storage/source refusal precedes any archive creation or deletion.
    return [inspect_checkout(root) for root in checkouts]


def verify_archive(path, records):
    found = set()
    with tarfile.open(path, "r:gz") as saved:
        for member in saved:
            relative = member.name
            if relative not in records or relative in found:
                raise RuntimeError("Unexpected archive member: " + relative)
            found.add(relative)
            row = records[relative]
            if member.mode != stat.S_IMODE(row["stamp"][0]):
                raise RuntimeError("Archive permissions mismatch: " + relative)
            if row["kind"] == "file":
                if not member.isfile() or member.size != row["stamp"][1]:
                    raise RuntimeError("Archive file type/size mismatch: " + relative)
                stream = saved.extractfile(member)
                if stream is None:
                    raise RuntimeError("Missing archive content: " + relative)
                with stream:
                    if digest(stream) != row["sha256"]:
                        raise RuntimeError("Archive content mismatch: " + relative)
            elif row["kind"] == "link":
                if not member.issym() or member.linkname != row["link"]:
                    raise RuntimeError("Archive symlink mismatch: " + relative)
            elif not member.isdir():
                raise RuntimeError("Archive directory mismatch: " + relative)
    if found != set(records):
        raise RuntimeError("Missing archive members")


def archive_and_retire(item, destination):
    root = Path(item["path"])
    archive, manifest, partial = archive_paths(root, destination)
    no_links(destination)
    no_links(root)
    unchanged(root, item["snapshot"], "before archiving")
    records = item["entries"]
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    owned_partial = None
    try:
        with partial.open("xb") as raw:
            info = os.fstat(raw.fileno())
            owned_partial = (info.st_dev, info.st_ino)
            os.chmod(partial, 0o600)
            with tarfile.open(fileobj=raw, mode="w:gz", compresslevel=1,
                              dereference=False) as output:
                for relative, row in records.items():
                    path = root if relative == "." else root / relative
                    if stamp(path) != row["stamp"]:
                        raise RuntimeError("Source changed before archiving: " + str(path))
                    member = output.gettarinfo(str(path), arcname=relative)
                    if row["kind"] == "file":
                        with path.open("rb") as source:
                            row["sha256"] = digest(source)
                            source.seek(0)
                            # Regular members keep validation independent of tar hardlink lookup.
                            member.type = tarfile.REGTYPE
                            member.linkname = ""
                            member.size = row["stamp"][1]
                            output.addfile(member, source)
                    else:
                        output.addfile(member)
                    if stamp(path) != row["stamp"]:
                        raise RuntimeError("Source changed while archiving: " + str(path))
            raw.flush()
            os.fsync(raw.fileno())
        verify_archive(partial, records)
        unchanged(root, item["snapshot"], "after archive verification")
        if os.fsdecode(git(root, "status", "--porcelain=v1", "--untracked-files=all")) != item["status"]:
            raise RuntimeError("Git status changed before retirement: " + str(root))
        no_links(destination)
        # Publishing by hardlink refuses existing destinations instead of overwriting them.
        os.link(partial, archive)
        partial.unlink()
        owned_partial = None
        with archive.open("rb") as source:
            item["archive_sha256"] = digest(source)
        item["archive"] = str(archive)
        item["restore"] = "Extract the tar.gz into an empty restore directory; Git metadata is included."
        saved_item = {key: value for key, value in item.items() if key != "snapshot"}
        with manifest.open("x") as stream:
            os.chmod(manifest, 0o600)
            json.dump(saved_item, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        with archive.open("rb") as stream:
            os.fsync(stream.fileno())
        directory_fd = os.open(str(destination), os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        no_links(archive)
        verify_archive(archive, records)
        with archive.open("rb") as source:
            if digest(source) != item["archive_sha256"]:
                raise RuntimeError("Published archive checksum changed: " + str(archive))
        # Last source inspection follows all archive/manifest publication and fsyncs.
        unchanged(root, item["snapshot"], "immediately before retirement")
        shutil.rmtree(root)
        print("Retired checkout: {} (verified archive: {})".format(root, archive), flush=True)
    finally:
        if owned_partial is not None and (partial.exists() or partial.is_symlink()):
            current = partial.lstat()
            if (current.st_dev, current.st_ino) == owned_partial:
                partial.unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--project-caches", type=Path, action="append", metavar="ROOT")
    mode.add_argument("--retire-checkouts", type=Path, action="append", metavar="ROOT")
    parser.add_argument("--archive-root", type=Path, metavar="PATH")
    parser.add_argument("--execute", action="store_true", help="apply the displayed cleanup; default is preview")
    args = parser.parse_args(argv)
    if args.retire_checkouts and args.archive_root is None:
        parser.error("--retire-checkouts requires --archive-root")
    if args.project_caches and args.archive_root is not None:
        parser.error("--archive-root is only used with --retire-checkouts")
    roots = [checked_path(path) for path in (args.project_caches or args.retire_checkouts)]
    check_disjoint(roots, "requested roots")
    if args.execute and not shutil.rmtree.avoids_symlink_attacks:
        raise RuntimeError("This Python/platform cannot safely remove directories without following symlinks")
    if args.project_caches:
        skipped = []
        plan = cache_plan(roots, skipped=skipped)
        for path, reason in skipped:
            print("[keep] {} ({})".format(path, reason), flush=True)
        for row in plan:
            print("{}Cache: {} ({} KiB allocated; Git owner: {})".format(
                "" if args.execute else "[dry-run] ", row["path"], row["kib"], row["owner"]), flush=True)
        print("{} cache directories; {} KiB allocated".format(
            len(plan), sum(row["kib"] for row in plan)), flush=True)
        if args.execute:
            execute_cache_cleanup(plan)
    else:
        destination = checked_path(args.archive_root, must_exist=False)
        for requested in roots:
            if destination == requested or requested in destination.parents:
                raise RuntimeError("Archive root is inside a selected discovery root")
        plan = retirement_plan(roots, destination)
        if not plan:
            print("Nothing to retire: selected directories contain no Git checkouts", flush=True)
        for item in plan:
            archive, _, _ = archive_paths(Path(item["path"]), destination)
            print("{}Retire checkout: {} ({} KiB allocated)".format(
                "" if args.execute else "[dry-run] ", item["path"], item["allocated_kib"]), flush=True)
            print("  Recovery archive: " + str(archive), flush=True)
            for relative in item["excluded_caches"]:
                print("  Omit rebuildable cache: " + str(Path(item["path"]) / relative), flush=True)
        if args.execute:
            # Check all snapshots before publishing the first archive.
            for item in plan:
                unchanged(Path(item["path"]), item["snapshot"], "before retirement batch")
            for item in plan:
                archive_and_retire(item, destination)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, tarfile.TarError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(1)
