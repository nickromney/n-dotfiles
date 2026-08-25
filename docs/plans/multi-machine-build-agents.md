# Multi-machine build-agent plan

Status: proposed

This plan turns the three available computers into one small, deliberately
boring development system:

- `m1` — 8 GB Mac mini, daily driver and Slicer host
- `m4` — 16 GB Mac mini, dedicated Docker/build host and Codex Computer Use host
- `lin1` — 16 GB Omarchy ThinkPad, Linux Slicer/build host

The names are short operational aliases. The repository should describe
portable roles and capabilities, while local SSH configuration maps those
roles to `m1`, `m4`, and `lin1`.

## Target topology

| Host | Role | Always-on workload | Deliberately absent |
| --- | --- | --- | --- |
| `m1` | `mac-driver` | Daily applications, terminal, Slicer-mac | Docker Desktop, build caches |
| `m4` | `mac-build` | Docker Desktop, build jobs, Codex desktop | Slicer-mac, personal iCloud data |
| `lin1` | `linux-build` | Slicer, Linux-native builds, optional agent jobs | macOS applications, iCloud |

Slicer licensing remains unmanaged and machine-local. The two licences are
used by `m1` (`slicer-mac`) and `lin1` (`slicer`). The M4 is not a Slicer host.
This avoids the known resource contention between Docker Desktop and
SlicerVM.

## M4 reinstall policy

Reinstall the M4 as a new Mac rather than migrating the current environment.
Do not restore applications, settings, or user data through Migration
Assistant.

During Setup Assistant:

- create the local build account;
- choose **Set Up Later** for the Apple Account;
- enable FileVault;
- avoid iCloud Drive, Desktop/Documents, Photos, Messages, Passwords, and
  other personal synchronization;
- install 1Password and use its CLI/SSH-agent integration for credentials;
- enable Find My only if the operational benefit outweighs the additional
  Activation Lock dependency during future erases.

The M1 remains the iCloud-enabled personal machine. The M4 may receive an
Apple Account later for a specific need, but that is an exception rather than
part of the build-host baseline.

## External storage policy

Use the 2 TB USB-C SSD for Docker's complete Docker Desktop disk image, not
for an ad-hoc `/var/lib/docker` mount. Configure it in Docker Desktop under
Resources → Advanced → Disk image location.

Format the drive as GUID Partition Map with APFS (preferably encrypted). Keep
the SSD directly connected to the M4 and treat removal or disconnection as a
Docker-host outage.

Suggested APFS volumes:

- `M4-Build-Docker` — Docker Desktop disk image, containerd image store,
  disposable Kubernetes data, and large build caches
- `M4-Build-Backup` — local export staging only; not the sole backup of the
  Docker volume or source code

Keep source checkouts, operating-system data, and small working files on the
internal SSD. Add a health check that warns below 80 GB internal free space
and below a separately chosen external-drive threshold.

## Repository changes

### 1. Split Mac package manifests

Keep `Brewfile` as the full `m1` daily-driver manifest. Add a minimal build
manifest, such as `Brewfile.build-mac`, for `m4`.

The build manifest should include Docker Desktop, Git, OpenSSH, mise, Stow,
tmux, build utilities, and the tools needed by the repository's validation
and build workflows. It should omit personal GUI applications, Mac App Store
applications, and Slicer.

The current `bootstrap.sh` and Makefile should accept an explicit Brewfile
selection rather than assuming every Mac is a personal Mac.

### 2. Add explicit host roles

Introduce a small, non-secret role layer with names such as:

```text
mac-driver
mac-build
linux-build
```

The role should control package selection, optional Stow trees, service
expectations, and validation. `m1`, `m4`, and `lin1` remain local host aliases,
not tracked machine-specific directories.

### 3. Add build-host health checks

Provide a read-only command that checks:

- OS and architecture;
- host identifier and declared role;
- required commands;
- Docker context and daemon health on `m4`;
- external Docker volume mounted at the expected path;
- internal and external free space;
- SSH reachability from the initiating machine;
- Slicer presence only on `m1` and `lin1`;
- absence of conflicting long-running runtimes where relevant.

The command should be safe to run from login shell startup diagnostics and CI
without mutating the host.

### 4. Add remote job primitives

Start with SSH and explicit commands, not a custom queue service:

```text
build submit m4 <project> ...
build status m4 <job-id>
build logs m4 <job-id>
build cancel m4 <job-id>
build artifacts m4 <job-id>
```

Jobs should run in a durable remote `tmux` session or equivalent service,
write logs and artifacts to a predictable job directory, and return a small
machine-readable status record. The initial implementation can use Git
commit/worktree references rather than copying arbitrary working directories.

### 5. Define Docker access safely

Use an SSH-backed Docker context from `m1` and `lin1` to `m4` where remote
Docker access is needed. Do not expose an unauthenticated Docker TCP socket.

The public repository may document context creation, but hostnames, ports,
and private network details belong in local SSH configuration.

### 6. Make Slicer placement explicit

Keep Slicer outside Brewfile and mise, as it is today. Add role-aware
documentation and checks:

- `m1`: install and activate `slicer-mac`; keep Docker Desktop off
- `lin1`: install and activate `slicer`; retain the Omarchy/Arkade Docker
  arrangement required by SlicerVM
- `m4`: do not install Slicer; run Docker Desktop as the build runtime

The existing Slicer installer should remain opt-in and default to dry-run.

## Rollout order

1. Back up M4 data, credentials, SSH configuration, important repositories,
   and any Docker data worth retaining.
2. Prepare and verify the external SSD; do not erase it until its contents
   have been independently checked.
3. Reinstall M4 and establish the local account, FileVault, networking, and
   1Password before applying dotfiles.
4. Add the build Mac manifest and bootstrap selection to this repository.
5. Install Docker Desktop and move its disk image to the external SSD.
6. Verify Docker, external storage, disk thresholds, and native arm64 tools.
7. Configure Codex desktop and Computer Use on M4.
8. Add SSH aliases and test M1 → M4 access with a harmless command.
9. Implement one end-to-end build job with logs and artifact retrieval.
10. Validate Slicer independently on M1 and `lin1`; do not introduce Docker
    Desktop to either machine merely to make the manifests symmetrical.

## Acceptance criteria

The plan is complete when:

- a clean M4 can be rebuilt using a documented build-host command;
- no personal iCloud data is required on M4;
- Docker data lives on the external SSD and its absence produces a clear
  diagnostic;
- `m1` can submit, monitor, cancel, and collect one build on `m4`;
- build logs and artifacts survive terminal disconnects;
- Slicer works independently on `m1` and `lin1`;
- the same public repository remains usable without exposing private hostnames,
  credentials, or machine-specific paths;
- all new setup and job interfaces have dry-run/help behavior and tests.

## Non-goals for the first iteration

- a general-purpose distributed scheduler;
- automatic job placement across all three hosts;
- exposing Docker over the LAN;
- running local language models on M4;
- moving personal applications or iCloud state onto M4;
- managing Slicer licences through Homebrew, mise, or the public repository.
