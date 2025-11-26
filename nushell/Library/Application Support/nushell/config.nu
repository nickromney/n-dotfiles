# config.nu
#
# Installed by:
# version = "0.103.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu
#
# See `help config nu` for more options
#
# You can remove these comments if you want or leave
# them for future reference.

$env.config.buffer_editor = "nvim"
$env.config.show_banner = false
$env.config.edit_mode = 'vi'
$env.config.menus = [
      {
        name: completion_menu
        only_buffer_difference: false # Search is done on the text written after activating the menu
        marker: "⎁ "                  # Indicator that appears with the menu is active
        type: {
            layout: columnar          # Type of menu
            columns: 4                # Number of columns where the options are displayed
            col_width: 20             # Optional value. If missing all the screen width is used to calculate column width
            col_padding: 2            # Padding between columns
        }
        style: {
            text: green                   # Text style
            selected_text: green_reverse  # Text style for selected option
            description_text: yellow      # Text style for description
        }
      },
       {
        name: history_menu
        only_buffer_difference: false # Search is done on the text written after activating the menu
        marker: "⌂ "                 # Indicator that appears with the menu is active
        type: {
            layout: list             # Type of menu
            page_size: 10            # Number of entries that will presented when activating the menu
        }
        style: {
            text: green                   # Text style
            selected_text: green_reverse  # Text style for selected option
            description_text: yellow      # Text style for description
        }
      }
]
$env.config.completions.algorithm = "fuzzy"
$env.config.keybindings = [
     {
      name: change_dir_with_fzf
      modifier: control
      keycode: char_f
      mode: [ emacs, vi_normal, vi_insert ],
      event: {
        send: executehostcommand,
        cmd: "F"
      }
    },
    {
    name: fuzzy_history_fzf
    modifier: control
    keycode: char_r
    mode: [emacs , vi_normal, vi_insert]
    event: {
      send: executehostcommand
      cmd: "commandline edit --replace (
        history
          | get command
          | reverse
          | uniq
          | str join (char -i 0)
          | fzf --scheme=history --read0 --tiebreak=chunk --layout=reverse --preview='echo {..}' --preview-window='bottom:3:wrap' --bind alt-up:preview-up,alt-down:preview-down --height=70% -q (commandline) --preview='echo -n {} | nu --stdin -c \'nu-highlight\''
          | decode utf-8
          | str trim
      )"
    }
  }
]

export-env {
    $env.BROWSER = "firefox"
    $env.XDG_CONFIG_HOME = $"($env.HOME)/.config"
    $env.PAGER = if ((which bat | length) > 0) { "bat" } else { "less" }
    $env.BAT_PAGER = "less"
    $env.BAT_THEME = "gruvbox-dark"
}

use std/dirs
use std/log
use std/util "path add"

# Path additions are handled in env.nu

# Navigation
def --env cdd [] {
    let developer_dir = $"($env.HOME)/Developer"
    if ($developer_dir | path exists) {
        cd $developer_dir
    } else {
        print $"Developer directory not found: ($developer_dir)"
    }
}

# Make or activate virtual python environment. Note that nushell variables from the current shell are not passed as this is a new subshell!
def mkenv [envname?: string] {
    #this will launch a subshell so non-environment variables from current shell are lost
    if ($envname == "" or $envname == null) {
        mkenv "env"
    } else {
        if not ($envname | path exists) { virtualenv $envname };  nu -e $"$env.VIRTUAL_ENV_DISABLE_PROMPT = true; overlay use ($envname)/bin/activate.nu; "
    }
}

def --wrapped man [...args] {
    $env.GROFF_NO_SGR = 1
    $env.LESS_TERMCAP_mb = ansi --escape '01;31m'  #\E[01;31m'
    $env.LESS_TERMCAP_md = ansi --escape '01;38;5;74m'  #\E[01;38;5;74m'
    $env.LESS_TERMCAP_me = ansi reset
    $env.LESS_TERMCAP_se = ansi reset
    $env.LESS_TERMCAP_ue = ansi reset
    $env.LESS_TERMCAP_us = ansi --escape '04;38;5;146m' #$'\E[04;38;5;146m'
    ^man ...$args
}

# Git aliases
alias gs = git status
alias gc = git commit

# Conditional aliases need to be functions
def g [] {
    if ((which lazygit | length) > 0) {
        lazygit
    } else {
        git
    }
}

# File listing aliases
def l [...args] {
    if ((which eza | length) > 0) {
        if ($args | length) > 0 {
            eza --oneline ...$args
        } else {
            eza --oneline
        }
    } else {
        # Nushell's ls doesn't have -1 flag, just use ls
        if ($args | length) > 0 {
            ls ...$args
        } else {
            ls
        }
    }
}

alias ll = ls -la

def tree [...args] {
    if ((which eza | length) > 0) {
        if ($args | length) > 0 {
            eza --tree ...$args
        } else {
            eza --tree
        }
    } else {
        echo "eza not installed"
    }
}

# Editor aliases
alias n = nvim
alias vi = nvim
alias vim = nvim

# Utility aliases
alias sz = exec nu  # Reload nushell


# FZF aliases/functions
def f [] {
    if ((which fzf | length) > 0) {
        fzf
    } else {
        print "fzf is not installed"
    }
}

# Browse files with fzf + bat preview
def bf [] {
    if ((which fzf | length) > 0) and ((which bat | length) > 0) {
        let selected = (fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | str trim)
        if ($selected | str length) > 0 {
            bat $selected
        }
    } else {
        print "Both fzf and bat need to be installed"
    }
}

# Open file in nvim using fzf
def nf [] {
    if ((which fzf | length) > 0) and ((which nvim | length) > 0) {
        let selected = (
            if ((which bat | length) > 0) {
                fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | str trim
            } else {
                fzf | str trim
            }
        )
        if ($selected | str length) > 0 {
            nvim $selected
        }
    } else {
        print "Both fzf and nvim need to be installed"
    }
}

# Copy file path to clipboard (macOS)
def pf [] {
    if $nu.os-info.name == "macos" and ((which fzf | length) > 0) and ((which pbcopy | length) > 0) {
        let selected = (
            if ((which bat | length) > 0) {
                fzf --preview='bat --color=always --style=numbers --line-range=:500 {}' | str trim
            } else {
                fzf | str trim
            }
        )
        if ($selected | str length) > 0 {
            $selected | pbcopy
            print $"Copied ($selected) to clipboard"
        }
    } else {
        print "This command requires fzf and pbcopy (macOS)"
    }
}

# AWS Lambda virtual environment activation
def aws-lambda-env [] {
    let venv_path = $"($env.HOME)/.venvs/aws-lambda"
    if ($venv_path | path exists) {
        print "AWS Lambda virtual environment found"
        print "To activate it, run one of these commands:"
        print "  overlay use ~/.venvs/aws-lambda/bin/activate.nu"
        print "Or manually set environment:"
        print "  $env.VIRTUAL_ENV = '~/.venvs/aws-lambda'"
        print "  $env.PATH = ($env.PATH | prepend '~/.venvs/aws-lambda/bin')"
    } else {
        print $"AWS Lambda virtual environment not found at ($venv_path)"
        print "To create it: python -m venv ~/.venvs/aws-lambda"
    }
}

# Load local environment if it exists
# Note: source requires a literal path, so we can't use dynamic paths
# If you have a local env.nu file, add this line manually:
# source ~/.local/bin/env.nu

# Source external tools (generated in env.nu)
# env.nu creates stub files for missing tools, so these sources won't fail
source ($nu.data-dir | path join "vendor/autoload/starship.nu")
source ~/.zoxide.nu
source ($nu.data-dir | path join "vendor/autoload/uv-completions.nu")

# Zoxide alias (z is defined by zoxide init or stub in env.nu)
alias o = z

$env.config.hooks.env_change.PWD = [
  { || if (which direnv | is-empty) { return }; direnv export json | from json | default {} | load-env }
]
