# n-dotfiles

An opinionated dotfiles setup designed to:

- work on Mac OS X with brew
- work on Ubuntu (particularly in dev containers and for GitHub Actions)
- be extensible to add other package managers

## Design considerations

- I work on Mac OS X
- I'm trying to move to use dev containers
- I'm a DevOps Engineer by recent training, so like idempotent code

I looked at [nix flakes](https://nixos.wiki/wiki/flakes) but although I'm often tweaking my configuration, I don't need to set up whole new machines enough to warrant it. This [blog](https://jvns.ca/blog/2023/11/11/notes-on-nix-flakes/) from Julia Evans convinced me away from it.

## Installation

1. Clone the repository:

```bash
git clone https://github.com/nickromney/n-dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

1. Install desired package managers:

- `arkade`: Optional, for CLI tools from [alexellis/arkade](https://github.com/alexellis/arkade?tab=readme-ov-file#getting-arkade)
- `brew`: Optional, for packages and casks from [brew.sh](https://brew.sh/)
- `uv`: Optional, for Python tools from [astral.sh](https://docs.astral.sh/uv/getting-started/installation/#installing-uv)

1. Run installation and configuration:

```bash
./install.sh [-d|--dry-run] [-v|--verbose] [-s|--stow] [-f|--force] [-h|--help]
```

## Features

- Automatically detects available package managers
- Skips unavailable package managers without failing
- Installs only tools that match available package managers
- Uses GNU Stow for configuration management
- Force mode (`-f`) to handle existing configurations

## Usage

```bash
# Install packages only
./install.sh

# Install packages and stow configurations
./install.sh -s

# Preview changes without making them
./install.sh -d -s

# Force stow to adopt existing files
./install.sh -s -f
```

## Configuration

Edit `tools.yaml` to modify:

- Package manager configurations
- Tool specifications and dependencies
- Installation methods and verification commands

Examples for each type:

### Tap a Homebrew repository

```yaml
noahgorstein/tap:
  manager: brew
  type: tap
  check_command: "brew tap | grep -q '^noahgorstein/tap$'"
  install_args: []
```

### Install a Homebrew cask application

```yaml
kitty:
  manager: brew
  type: cask
  check_command: 'brew list --cask kitty >/dev/null 2>&1 || [ -d "/Applications/kitty.app" ] || which kitty >/dev/null 2>&1'
  install_args: []
```

### Install a Homebrew package

```yaml
bat:
  manager: brew
  type: package
  check_command: "bat --version"
  install_args: []
```

### Install a tool via arkade

```yaml
atuin:
  manager: arkade
  type: get
  check_command: "test -f $HOME/.arkade/bin/atuin"
  install_args: []
```

### Install a Python tool via uv

```yaml
posting:
  manager: uv
  type: tool
  check_command: "which posting >/dev/null 2>&1"
  install_args: ["--python", "3.12"]
```

Each tool entry requires:

```yaml
manager: Package manager to use (brew/arkade/uv)
type: Installation method specific to the manager
check_command: Command to verify installation
install_args: Additional installation arguments (optional)
```

## Directory Structure

```shell
.
├── install.sh    # Package installation and configuration management
├── tools.yaml   # Package definitions
└── */           # Tool configurations, where each directory represents a stow target
```

## Inspiration

- [idcrook](https://github.com/idcrook/i-dotfiles) - elegant usage of GNU stow
- [Typecraft Dev](https://github.com/typecraft-dev/dotfiles) - because of the excellent YouTube video walkthroughs - "be a better nerd"
- [Omer Hamerman / DevOpsToolbox](https://github.com/omerxx/dotfiles) - again, a fan of the YouTube video walkthroughs
- [Christian Sutter](https://github.com/csutter/punkt) - I used to work with Christian, and learned lots from pair programming with him.
- [Rob / Tech Craft](https://www.youtube.com/@tech_craft/videos) - Not posted for a while, but excellent videos
