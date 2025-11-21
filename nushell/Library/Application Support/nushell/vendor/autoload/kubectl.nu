# kubectl completions and aliases
#
# NOTE: Aliases are defined in scripts/kubectl-aliases.sh (canonical source)
#       These nushell aliases mirror that file but use nushell syntax
#
# Completions are not auto-generated because nushell's 'source' command requires
# files to exist at parse time. To enable kubectl completions manually:
#   mkdir ~/.cache/kubectl
#   kubectl completion nu | save --force ~/.cache/kubectl/completions.nu
# Then add to your config: source ~/.cache/kubectl/completions.nu
#
# Note: These aliases are defined unconditionally. They will only work if kubectl
# is installed and in your PATH.

# kubectl aliases (mirrored from scripts/kubectl-aliases.sh)
export alias k = kubectl

# Get commands
export alias kgp = kubectl get pods
export alias kgs = kubectl get services
export alias kgd = kubectl get deployments
export alias kgn = kubectl get nodes
export alias kgi = kubectl get ingress

# Describe and logs
export alias kd = kubectl describe
export alias kl = kubectl logs
export alias klf = kubectl logs -f

# Exec
export alias ke = kubectl exec -it

# Apply and delete
export alias ka = kubectl apply -f
export alias kdel = kubectl delete

# Context and namespace
export alias kctx = kubectl config current-context
export alias kns = kubectl config set-context --current --namespace
