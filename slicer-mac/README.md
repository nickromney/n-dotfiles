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
