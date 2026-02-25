# slicer-mac

Configuration for [slicer-mac](https://slicervm.com).

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
