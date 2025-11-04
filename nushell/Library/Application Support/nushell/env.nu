# env.nu - Environment variables and tool initialization

# Basic environment variables
$env.EDITOR = "nvim"
$env.SUDO_EDITOR = $env.EDITOR
$env.LANG = "en_GB.UTF-8"

# History configuration
$env.HISTFILE = $"($env.HOME)/.zsh_history"  # Keep compatibility with zsh history location

# PATH Management
$env.PATH = ($env.PATH | split row (char esep) | prepend [
    "/opt/homebrew/bin"  # Add homebrew first for macOS
    "/opt/homebrew/opt/python@3.11/bin"  # Python 3.11
    $"($env.HOME)/.local/bin"
    $"($env.HOME)/.arkade/bin"
    $"($env.HOME)/.cargo/bin"
    $"($env.HOME)/.tfenv/bin"
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"  # VSCode CLI
] | where { |p| $p | path exists } | uniq | str join (char esep))

# ZScaler Certificates
let zscaler_cert_dir = $"($env.HOME)/.zscalerCerts"
if ($zscaler_cert_dir | path exists) {
    let zscaler_ca_bundle = $"($zscaler_cert_dir)/zscalerCAbundle.pem"
    let azure_ca_cert = $"($zscaler_cert_dir)/azure-cacert.pem"

    if ($zscaler_ca_bundle | path exists) {
        $env.AWS_CA_BUNDLE = $zscaler_ca_bundle
        $env.CURL_CA_BUNDLE = $zscaler_ca_bundle
        $env.GIT_SSL_CAPATH = $zscaler_ca_bundle
        $env.NODE_EXTRA_CA_CERTS = $zscaler_ca_bundle
        $env.SSL_CERT_FILE = $zscaler_ca_bundle
    }

    if ($azure_ca_cert | path exists) {
        $env.REQUESTS_CA_BUNDLE = $azure_ca_cert
    }
}

# 1Password SSH Agent Setup
if ((which op | length) > 0) {
    # Check OS type
    if $nu.os-info.name == "macos" {
        # macOS
        let op_socket_path = $"($env.HOME)/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
        if ($op_socket_path | path exists) {
            # Create ~/.1password directory if needed
            mkdir $"($env.HOME)/.1password"

            # Create symlink for easier access
            let symlink_path = $"($env.HOME)/.1password/agent.sock"
            if not ($symlink_path | path exists) {
                ^ln -sf $op_socket_path $symlink_path
            }

            $env.SSH_AUTH_SOCK = $symlink_path
        }
    } else {
        # Linux
        let op_socket_path = $"($env.HOME)/.1password/agent.sock"
        if ($op_socket_path | path exists) {
            $env.SSH_AUTH_SOCK = $op_socket_path
        }
    }
}

# FNM (Fast Node Manager) - supports .node-version files
if ((which fnm | length) > 0) {
    # Load FNM environment variables
    load-env (fnm env --shell bash
        | lines
        | str replace 'export ' ''
        | str replace -a '"' ''
        | split column "="
        | rename name value
        | where name != "FNM_ARCH" and name != "PATH"
        | reduce -f {} {|it, acc| $acc | upsert $it.name $it.value }
    )

    # Add FNM_MULTISHELL_PATH to PATH
    $env.PATH = ($env.PATH
        | split row (char esep)
        | prepend $"($env.FNM_MULTISHELL_PATH)/bin"
        | uniq
        | str join (char esep)
    )
}

# Podman socket for Docker compatibility
if ((which podman | length) > 0) {
    # Try to get podman socket path
    let podman_result = (do { podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' } | complete)
    if $podman_result.exit_code == 0 and ($podman_result.stdout | str trim) != "" {
        $env.DOCKER_HOST = $"unix://($podman_result.stdout | str trim)"
    }
}

# Initialize external tools
mkdir ($nu.data-dir | path join "vendor/autoload")

# Starship
if ((which starship | length) > 0) {
    starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
}

# Zoxide
if ((which zoxide | length) > 0) {
    zoxide init nushell | save -f ~/.zoxide.nu
}

# UV completions
if ((which uv | length) > 0) {
    uv generate-shell-completion nushell | save -f ($nu.data-dir | path join "vendor/autoload/uv-completions.nu")
}
