# kubectl completions and aliases
# Only loads if kubectl is available
#
# NOTE: Aliases are defined in scripts/kubectl-aliases.sh (canonical source)
#       These nushell aliases mirror that file but use nushell syntax
#
# Completions are not auto-generated because nushell's 'source' command requires
# files to exist at parse time. To enable kubectl completions manually:
#   mkdir ~/.cache/kubectl
#   kubectl completion nu | save --force ~/.cache/kubectl/completions.nu
# Then add to your config: source ~/.cache/kubectl/completions.nu

if ((which kubectl | length) > 0) {
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
