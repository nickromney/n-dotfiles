# slicer-mac

Configuration for [slicer-mac](https://slicervm.com).

## Activation

Slicer needs periodic license activation, roughly monthly. If Slicer starts failing
with license or activation errors, refresh the local license:

```bash
slicer activate
```

This reads the GitHub access token from `$HOME/.slicer/gh-access-token`,
exchanges it for a Slicer license, and writes the license to
`$HOME/.slicer/LICENSE`.

## PATH Setup

The [installation docs](https://docs.slicervm.com/mac/installation/#install-the-binaries) assume
`~/slicer-mac` is on your PATH, but `slicer install` does not add it. Without this you'll see:

```text
zsh: command not found: slicer-mac
```

Add `~/slicer-mac` to PATH in `~/.zshrc` (this dotfiles repo handles this in `zsh/.zshrc`):

```bash
export PATH="$HOME/slicer-mac:$PATH"
```

Then re-source your shell. With it on the PATH, the binaries work as expected:

```bash
slicer-mac up
slicer-tray --url ./slicer.sock --terminal "ghostty"
```

## Service Restarts

Restart slicer-mac services as your login user, not with `sudo`. These are
per-user launchd services, and running the commands with `sudo` targets `gui/0`
instead of your user domain.

```bash
slicer-mac service restart tray
slicer-mac service restart daemon
```

Or use the helper:

```bash
./restart-slicer-mac.sh --execute
```

## Setup

```bash
curl -sLS https://get.slicervm.com | sudo bash
slicer install slicer-mac ~/slicer-mac
cd ~/slicer-mac
yq < slicer-mac.yaml
mkdir -p $HOME/Developer/personal/n-dotfiles/slicer-mac/slicer-mac
cp slicer-mac.yaml $HOME/Developer/personal/n-dotfiles/slicer-mac/slicer-mac/slicer-mac.yaml
rm slicer-mac.yaml
stow --dir=$HOME/Developer/personal/n-dotfiles --target=$HOME --verbose=1 -R slicer-mac
```

## Removal and VM disks

Run the helper as your login user, **without sudo** (it uses sudo only for
system CLI files). Preview first:

```bash
./slicer-mac/remove-slicer-mac.sh --dry-run
./slicer-mac/remove-slicer-mac.sh --execute
```

Removal permanently deletes `~/slicer-mac` and `~/slicer`, including VM disks
inside them. It also checks this package and its nested `slicer-mac/` directory
for `slicer*.img`, `sbox*.img`, runtime caches, sockets and logs.

[Slicer storage documentation](https://docs.slicervm.com/mac/storage/) describes
raw, sparse `.img` disks, host-group base images, `kernel/` and `oci-cache/` in
the daemon's working directory. If you ran the daemon elsewhere or used custom
host-group names, explicitly add each dedicated runtime directory:

```bash
./slicer-mac/remove-slicer-mac.sh --dry-run --runtime-dir /path/to/slicer-runtime
./slicer-mac/remove-slicer-mac.sh --execute --no-input --runtime-dir /path/to/slicer-runtime
```

`--runtime-dir` is repeatable and removes **all top-level `.img` files** plus
known runtime state there. It preserves the directory, YAML configuration and
other files; it does not recursively search shared folders. Review the preview
before executing. The helper waits for Slicer processes to stop and refuses disk
deletion if they remain running. `--execute` is explicit deletion consent;
there are no interactive prompts apart from sudo authentication when required.

Credentials and license files in `~/.slicer` are retained. The helper does not
search the whole machine, erase backups or remove macOS background-item records;
check Login Items & Extensions manually after removal.
