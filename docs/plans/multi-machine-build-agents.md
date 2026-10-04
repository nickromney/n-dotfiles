# Multi-machine build-agent plan

Status: proposed

This plan describes portable roles for a small development system:

- `mac-driver` — daily applications and an optional Slicer-mac host
- `mac-build` — dedicated Docker/build host and Codex Computer Use host
- `linux-build` — Linux-native builds and an optional Slicer host

These are example roles, not an inventory of actual computers. Local SSH
configuration maps the roles to machine names. Hardware inventory, storage
names, licence allocation, and account placement remain machine-local.

## Target topology

| Role | Always-on workload | Deliberately absent |
| --- | --- | --- |
| `mac-driver` | Daily applications, terminal, optional Slicer-mac | Docker Desktop, build caches |
| `mac-build` | Docker Desktop, build jobs, Codex desktop | Slicer-mac, personal iCloud data |
| `linux-build` | Linux-native builds, optional Slicer and agent jobs | macOS applications, iCloud |

Slicer licensing remains unmanaged and machine-local. Keep SlicerVM and
Docker Desktop on separate hosts to avoid resource contention.

## Build Mac reinstall policy

Reinstall a build Mac as a new Mac rather than migrating an existing environment.
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

A build host may receive an Apple Account later for a specific need, but that
is an exception rather than part of the build-host baseline. Personal account
placement on other hosts is outside this plan.

## External storage policy

Use a suitably sized external SSD for Docker's complete Docker Desktop disk
image, not for an ad-hoc `/var/lib/docker` mount. Configure it in Docker Desktop under
Resources → Advanced → Disk image location.

Format the drive as GUID Partition Map with APFS (preferably encrypted). Keep
the SSD directly connected to the build Mac and treat removal or disconnection as a
Docker-host outage.

Example APFS volume roles; choose actual names locally:

- `Build-Docker` — Docker Desktop disk image, containerd image store,
  disposable Kubernetes data, and large build caches
- `Build-Backup` — local export staging only; not the sole backup of the
  Docker volume or source code

Keep source checkouts, operating-system data, and small working files on the
internal SSD. Add a health check with locally chosen internal and external
free-space thresholds.

## Repository changes

### 1. Split Mac package manifests

Keep `Brewfile` as the full daily-driver manifest. Add a minimal build
manifest, such as `Brewfile.build-mac`, for the `mac-build` role.

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
expectations, and validation. Actual host aliases remain local, without
tracked machine-specific directories.

### 3. Add build-host health checks

Provide a read-only command that checks:

- OS and architecture;
- host identifier and declared role;
- required commands;
- Docker context and daemon health on the build Mac;
- external Docker volume mounted at the expected path;
- internal and external free space;
- SSH reachability from the initiating machine;
- Slicer presence only on hosts assigned that workload locally;
- absence of conflicting long-running runtimes where relevant.

The command should be safe to run from login shell startup diagnostics and CI
without mutating the host.

### 4. Add remote job primitives

Start with SSH and explicit commands, not a custom queue service:

```text
build submit <build-host> <project> ...
build status <build-host> <job-id>
build logs <build-host> <job-id>
build cancel <build-host> <job-id>
build artifacts <build-host> <job-id>
```

Jobs should run in a durable remote `tmux` session or equivalent service,
write logs and artifacts to a predictable job directory, and return a small
machine-readable status record. The initial implementation can use Git
commit/worktree references rather than copying arbitrary working directories.

### 5. Define Docker access safely

Use an SSH-backed Docker context from client hosts to the build Mac where
remote Docker access is needed. Do not expose an unauthenticated Docker TCP socket.

The public repository may document context creation, but hostnames, ports,
and private network details belong in local SSH configuration.

### 6. Make Slicer placement explicit

Keep Slicer outside Brewfile and mise, as it is today. Add role-aware
documentation and checks:

- `mac-driver`: optionally install and activate `slicer-mac`; keep Docker Desktop off
- `linux-build`: optionally install and activate `slicer`; retain the Omarchy/Arkade Docker
  arrangement required by SlicerVM
- `mac-build`: do not install Slicer; run Docker Desktop as the build runtime

The existing Slicer installer should remain opt-in and default to dry-run.

## Rollout order

1. Back up build-host data, credentials, SSH configuration, important repositories,
   and any Docker data worth retaining.
2. Prepare and verify the external SSD; do not erase it until its contents
   have been independently checked.
3. Reinstall the build Mac and establish the local account, FileVault, networking, and
   1Password before applying dotfiles.
4. Add the build Mac manifest and bootstrap selection to this repository.
5. Install Docker Desktop and move its disk image to the external SSD.
6. Verify Docker, external storage, disk thresholds, and native arm64 tools.
7. Configure Codex desktop and Computer Use on the build Mac.
8. Add local SSH aliases and test client → build-host access with a harmless command.
9. Implement one end-to-end build job with logs and artifact retrieval.
10. Validate Slicer independently on its designated hosts; do not introduce Docker
    Desktop to either machine merely to make the manifests symmetrical.

## Acceptance criteria

The plan is complete when:

- a clean build Mac can be rebuilt using a documented build-host command;
- no personal iCloud data is required on the build Mac;
- Docker data lives on the external SSD and its absence produces a clear
  diagnostic;
- a client can submit, monitor, cancel, and collect one build on the build host;
- build logs and artifacts survive terminal disconnects;
- Slicer works independently on its designated hosts;
- the same public repository remains usable without exposing private hostnames,
  credentials, or machine-specific paths;
- all new setup and job interfaces have dry-run/help behavior and tests.

## Non-goals for the first iteration

- a general-purpose distributed scheduler;
- automatic job placement across multiple hosts;
- exposing Docker over the LAN;
- running local language models on the build Mac;
- moving personal applications or iCloud state onto the build Mac;
- managing Slicer licences through Homebrew, mise, or the public repository.
