# Nushell Config File
#
# See the documentation: https://www.nushell.sh/book/configuration.html

# Disable the welcome banner FIRST
$env.config.show_banner = false

# Use SQLite for history (better features than plaintext)
$env.config.history.file_format = "sqlite"

# Basic environment variables
$env.EDITOR = 'code'

# Ensure Homebrew is in PATH (for Apple Silicon Macs)
$env.PATH = ($env.PATH | split row (char esep) | prepend "/opt/homebrew/bin" | uniq)

# Simple aliases
alias ll = ls -la
alias la = ls -a
alias l = ls -l

# Git aliases
alias gs = git status
alias ga = git add
alias gc = git commit
alias gp = git push
alias gl = git log --oneline --graph

# Simple custom command example
def greet [name?: string] {
    let name = ($name | default "World")
    print $"Hello, ($name)!"
}

# Navigation shortcuts
def --env .. [] { cd .. }
def --env ... [] { cd ../.. }

# Set up Starship prompt if it hasn't been set up yet
let starship_file = ($nu.data-dir | path join "vendor/autoload/starship.nu")
if not ($starship_file | path exists) {
    mkdir ($nu.data-dir | path join "vendor/autoload")
    starship init nu | save -f $starship_file
}
