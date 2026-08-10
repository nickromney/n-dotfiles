# Omarchy / Arch companion setup

This package is the Linux counterpart to the personal Mac shortcut model.
It was designed against Omarchy **3.8.4** and keeps Omarchy's physical
Windows/Super key intact.

The source of truth for Omarchy's defaults remains Omarchy's own files under
`~/.local/share/omarchy`. Put personal changes in `~/.config`, especially
`~/.config/hypr/bindings.conf`; do not edit the files under
`~/.local/share/omarchy` because updates replace them.

## What this package adds

`keyd/default.conf` makes Caps Lock a real held Hyper modifier:

```text
Caps Lock (held) = Control + Alt + Shift + Super
Caps Lock (tap)  = Right Arrow
Left Shift + Right Shift = Caps Lock
```

`keyd` is packaged in Arch's official Extra repository and runs at the input
layer, below Wayland and Hyprland. Its modifier-layer syntax is documented in
the [keyd manual](https://github.com/rvaiya/keyd/blob/v2.6.0/docs/keyd.scdoc#L157-L201).
The physical Windows key therefore continues to trigger Omarchy's normal
`Super + …` bindings.

`hypr/hyper.conf` maps the Mac's named-workspace muscle memory onto five
numeric workspaces that suit a small laptop:

| Hyper key | Omarchy workspace | Role |
|---|---:|---|
| `W`, `I` | 1 | Web / work |
| `T`, `Y` | 2 | Terminal / development |
| `[`, `]` | 3 | Email / communication |
| `O`, `P` | 4 | Office / productivity |
| `U` | 5 | Utilities / files / Docker |
| `H` | previous | Former workspace |

Hyper+F and Hyper+S are intentionally left unclaimed for the mouse-hint and
scrolling layer. Omarchy's native `Super + 1…5`, `Super + Tab`, launcher, and
window-management bindings remain available.

## First application on Omarchy

`../bootstrap-omarchy.sh --dry-run` mechanizes the mechanical parts of this
walkthrough (pacman base packages, stow, keyd symlink/enable, the hyper.conf
include, `mise install`). This section documents the same steps by hand, plus
the parts that stay manual either way: 1Password sign-in, git SSH signing,
and mail client choice.

Use a second terminal or a TTY while changing keyboard input. `keyd` has a
panic sequence of **Backspace + Escape + Enter** if a bad mapping traps the
keyboard.

```bash
# Omarchy is Arch-based; keep its package manager as the system-package owner.
# No Homebrew/Brewfile on this path: mise (also in pacman's extra repo) owns
# the cross-platform CLI tool layer instead.
sudo pacman -S --needed git stow keyd mise zsh zsh-autosuggestions zsh-syntax-highlighting

git clone https://github.com/nickromney/n-dotfiles.git \
  ~/Developer/personal/n-dotfiles
cd ~/Developer/personal/n-dotfiles

# This repository is public: HTTPS cloning does not use SSH keys.
# Authenticate with GitHub later before pushing private repositories.

# Preview first. Select packages rather than importing every Mac-only tree.
./stow.sh --dry-run git zsh nvim tmux mise codex claude agents omarchy
./stow.sh git zsh nvim tmux mise codex claude agents omarchy

# keyd loads system configs, so expose the stowed file under a new name rather
# than replacing any existing /etc/keyd/default.conf.
sudo install -d /etc/keyd
sudo ln -s "$HOME/.config/keyd/default.conf" /etc/keyd/n-dotfiles.conf
sudo keyd check /etc/keyd/n-dotfiles.conf
sudo systemctl enable --now keyd
sudo keyd reload

# CLI tools and runtimes declared in mise/.config/mise/config.toml, now
# reachable at ~/.config/mise/config.toml via the stow above. This also
# provides shellcheck, bats, markdownlint-cli2, and yamllint — required for
# this repo's own `make lint` / `make test` and lefthook git hooks.
mise install

# Optional: install this repo's lefthook git hooks (pre-commit/pre-push).
make hooks
```

Add the personal Hyprland include once to `~/.config/hypr/bindings.conf`:

```ini
source = ~/.config/hypr/hyper.conf
```

Then reload Hyprland:

```bash
hyprctl reload
```

Do not stow the whole `~/.config/hypr` directory over Omarchy. The single
include keeps Omarchy's generated bindings and this personal layer separate.

## Files and Git layout

Linux does not require a different project layout. Keep the same portable
path you use on macOS:

```text
~/Developer/personal/
└── n-dotfiles/
```

On Arch, `~` is normally `/home/<your-login>`, so this is simply
`/home/<your-login>/Developer/personal`. You may use `~/src` or `~/code`
instead, but keeping `~/Developer/personal` makes existing scripts and muscle
memory carry over unchanged.

For a personal-only laptop, one global `~/.gitconfig` is enough. The
repository's `includeIf "gitdir:~/Developer/work/"` block is optional: leave
it dormant unless you later add work repositories with a different identity.
Do not create a multi-profile Git setup just for this machine.

The simplest personal setup is GitHub CLI over HTTPS:

```bash
gh auth login
```

The stowed `git/.gitconfig` already contains your personal identity, GitHub
CLI credential helper, editor, aliases, and default branch. Do not run generic
`git config --global …` or `gh auth setup-git` after stowing it: `~/.gitconfig`
is a symlink into this repository, so those commands would edit the tracked
source file. Inspect the active source with:

```bash
git config --global --list --show-origin
```

If you want Omarchy-only Git values without changing this checkout, omit the
`git` package from the Stow command and maintain a separate `~/.gitconfig`
there instead.

If you stow this repository's `git` package, disable SSH signing until a Linux
signer is installed; the tracked config currently contains the macOS
1Password signer path. This intentionally edits the stowed source file, so
review the resulting diff:

```bash
git config --file "$HOME/Developer/personal/n-dotfiles/git/.gitconfig" \
  commit.gpgsign false
git -C "$HOME/Developer/personal/n-dotfiles" diff -- git/.gitconfig
```

You can enable signing later with the Linux 1Password signer or a local SSH
signing key. Git authentication and commit signing are independent decisions.

To move existing repositories, push committed work from the Mac and clone it
on Omarchy:

```bash
mkdir -p ~/Developer/personal
cd ~/Developer/personal
git clone https://github.com/ORG/REPO.git
```

For files that are not yet pushed, use a deliberate one-way copy from the Mac
and inspect the destination before deleting anything on the source:

```bash
rsync -a --info=progress2 --exclude '.git/' \
  ~/Developer/personal/PROJECT/ \
  USER@OMARCHY_HOST:~/Developer/personal/PROJECT/
```

## Optional 1Password / SSH Git setup

The tracked Git config also contains the existing SSH-signing preference and
GitHub credential helper, but its 1Password signer path is macOS-specific. On
Omarchy either install 1Password and set its Linux signer path, or leave
signing disabled until the signer is present:

```bash
# Option A: 1Password's Linux signer (verify the path on the installed build)
git config --file "$HOME/Developer/personal/n-dotfiles/git/.gitconfig" \
  gpg.ssh.program /opt/1Password/op-ssh-sign

# Option B: temporary setup until signing is ready
git config --file "$HOME/Developer/personal/n-dotfiles/git/.gitconfig" \
  commit.gpgsign false
```

Authenticate GitHub while online:

```bash
gh auth login
```

The initial HTTPS clone works before SSH is configured. Switch remotes to SSH
after `gh auth login` and any required SSH key setup.

## Arkade / Docker

Keep the Docker installation that came with Arkade for SlicerVM; do not layer
another Docker package or daemon on top of it. Before using containers, record
the active context and daemon health:

```bash
docker context ls
docker version
docker info
```

If SlicerVM depends on a non-default context, leave that context selected for
the SlicerVM workflow and use an explicit `docker --context …` when testing a
different daemon.

## Mail

You are not locked into Thunderbird, but HEY is intentionally not a normal
IMAP mailbox. HEY supports SMTP for sending from connected addresses, but it
does not offer IMAP for reading mail in third-party clients. Use the official
HEY Linux app or an Omarchy web-app launcher for the full HEY workflow:

```bash
omarchy webapp install \
  "HEY" \
  "https://app.hey.com" \
  "https://www.google.com/s2/favicons?domain=app.hey.com&sz=128"
```

Then launch **HEY** with `Super + Space`. Omarchy stores these launchers in
`~/.local/share/applications`; the [web-app command](https://raw.githubusercontent.com/basecamp/omarchy/v3.8.4/bin/omarchy-webapp-install)
uses the browser-backed app without adding another package manager. HEY also
publishes a verified Linux Snap (`sudo snap install hey-mail`), but adding
`snapd` to an otherwise native Arch/Omarchy system is more machinery than I’d
start with.

For any separate IMAP/SMTP accounts, my shortlist is:

| Client | Best fit | Trade-off |
|---|---|---|
| **Mailspring** | Modern, clean Outlook alternative | Proprietary Electron app; some productivity features are Pro |
| **Geary** | Lightweight, calm conversation view | Deliberately fewer calendar/enterprise features |
| **Evolution** | Mail + calendar + contacts + Exchange | More Outlook-like and heavier |
| **Betterbird** | Thunderbird-compatible client with additional fixes | Still fundamentally Thunderbird; upstream package rather than Arch core |
| **aerc** | Terminal-first, keyboard/offline workflow | Not a graphical replacement |

For this laptop I’d use **HEY as its own app/PWA**, and **Mailspring** only if
you have another standard IMAP account. Install Geary or Evolution from Arch’s
repositories if you prefer a fully open-source stack; both are current Arch
packages ([Geary](https://archlinux.org/packages/extra/x86_64/geary/),
[Evolution](https://archlinux.org/packages/extra/x86_64/evolution/)).

## Omarchy defaults worth keeping

Omarchy 3.8.4 already provides the small-screen workflow: `Super + 1…5`
switches workspaces, `Super + Shift + 1…5` moves the current window, and
`Super + Space` opens Walker. `Super + K` shows all active bindings. Use
`Super + Alt + Space` for the Omarchy menu and its Install/Setup entries.
The [Omarchy manual](https://learn.omacom.io/2/the-omarchy-manual) documents
the defaults and the rule that personal overrides belong under `~/.config`.

## Cursor, Claude Code, and Slicer agents

Use workspace **2** for the coding stack: Cursor on the host, plus a terminal
for Claude Code/Codex and Slicer launches. From a project directory:

```bash
cursor .                         # host IDE, if the Cursor CLI is installed
claude                           # host Claude Code session
codex                            # host Codex CLI session

slicer claude .                  # isolated Claude Code VM for this project
slicer codex .                   # isolated Codex VM for this project
```

Slicer copies the working directory into a fresh VM and can install/configure
the selected agent for the launch. Use `--tmux=remote` when the agent should
survive terminal disconnects, or `--tmux=local` when you want the host tmux
session to own it. The [Slicer coding-agent guide](https://docs.slicervm.com/examples/coding-agents/)
lists the supported launchers and the isolation/authentication model.

Do the first launch of each Slicer agent while online: the VM may need to
download the agent and authenticate. Once the base VM and models are already
present, this remains the preferred isolated workflow on a weak connection.

## AI CLIs and weak Wi-Fi

Omarchy's current AI setup is deliberately lazy: its `codex`, `gemini`,
`copilot`, and `pi` launchers fetch npm packages on first use. On a good
connection, force those downloads before travelling:

```bash
claude --version
codex --version
opencode --version
```

For a persistent Codex CLI instead of Omarchy's `--prefer-online` wrapper,
install the official package into the user prefix after the first networked
setup:

```bash
mise use -g node@latest
npm install --global --prefix "$HOME/.local" @openai/codex
```

The Codex desktop app is not the Linux target; use the official Codex CLI.
OpenAI's current guidance says the CLI officially supports Linux and installs
with npm: [Codex CLI getting started](https://help.openai.com/en/articles/11096431).
Claude Code is also a CLI on Linux; Anthropic documents Node 18+, 4 GB RAM,
and its native installer / npm options here:
[Claude Code setup](https://docs.anthropic.com/en/docs/claude-code/getting-started).
Both cloud agents still need network access for authentication and inference.

Install Ollama through `Super + Alt + Space` → **Install** → **AI** →
**Ollama**, or use the official installer while online. Then prefetch only
models that fit the machine:

```bash
free -h
df -h "$HOME"
ollama serve                         # keep this running while pulling
ollama pull gemma3:4b                # 3.3 GB; general + image input
ollama pull qwen3:8b                 # 5.2 GB; small general/coding model
ollama pull gpt-oss:20b              # 14 GB; reasoning/agentic model
```

For a machine with at least 32 GB RAM (and enough disk), add the stronger
coding model:

```bash
ollama pull qwen3-coder:30b          # 19 GB; repository-scale coding
```

These sizes and capabilities are from the current Ollama model pages:
[Gemma 3](https://ollama.com/library/gemma3),
[Qwen 3](https://ollama.com/library/qwen3),
[gpt-oss](https://ollama.com/library/gpt-oss), and
[Qwen 3 Coder](https://ollama.com/library/qwen3-coder). Leave at least the
model size plus several GB for the OS, context, and applications; an older
laptop will usually prefer the 4B/8B models for interactive latency.

Codex can use the local OpenAI open-weight model without the OpenAI service:

```bash
codex --oss -m gpt-oss:20b
```

Ollama recommends a large context window (at least 64K for Codex integrations)
and documents the setup at [Codex with Ollama](https://docs.ollama.com/integrations/codex).
OpenCode and Claude Code can also be launched through Ollama's integration:

```bash
ollama launch opencode --model qwen3-coder:30b
ollama launch claude --model qwen3-coder:30b
```

Those two commands use the local model only after the integration and model
are already downloaded; account authentication and cloud models remain
network-dependent.

## Homerow-sized gap on Wayland

There is no mature Linux equivalent to Homerow's semantic accessibility labels
for arbitrary Wayland applications. Wayland intentionally restricts global
screen inspection and input injection. The closest current options are
coordinate-grid tools such as [Hyprwarp](https://github.com/bluedeep/hyprwarp)
or [Waywarp](https://github.com/Xuepoo/waywarp), and continuous mouse layers
such as [Mouseless](https://github.com/jbensmann/mouseless). They are useful,
but should be treated as opt-in experiments rather than a foundational
Omarchy dependency. Browser-specific labels (for example Vimium in Chromium)
are the most reliable semantic replacement today.
