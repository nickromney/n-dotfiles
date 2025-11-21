# kubectl completions and aliases
# Only loads if kubectl is available
#
# NOTE: Aliases are defined in scripts/kubectl-aliases.sh (canonical source)
#       These nushell aliases mirror that file but use nushell syntax

if ((which kubectl | length) > 0) {
    # Generate kubectl completions
    # Ensure kubectl cache directory exists and generate completions
    mkdir ~/.cache/kubectl
    try {
        kubectl completion nu | save --force ~/.cache/kubectl/completions.nu
        source ~/.cache/kubectl/completions.nu
    }

    # kubectl aliases (mirrored from scripts/kubectl-aliases.sh)
    alias k = kubectl

    # Get commands
    alias kgp = kubectl get pods
    alias kgs = kubectl get services
    alias kgd = kubectl get deployments
    alias kgn = kubectl get nodes
    alias kgi = kubectl get ingress

    # Describe and logs
    alias kd = kubectl describe
    alias kl = kubectl logs
    alias klf = kubectl logs -f

    # Exec
    alias ke = kubectl exec -it

    # Apply and delete
    alias ka = kubectl apply -f
    alias kdel = kubectl delete

    # Context and namespace
    alias kctx = kubectl config current-context
    alias kns = kubectl config set-context --current --namespace
}
