#!/usr/bin/env bash
#
# kubectl aliases - shared across bash and zsh
# Source this file after loading kubectl completion

# Short alias for kubectl
alias k='kubectl'

# Get commands
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kgi='kubectl get ingress'

# Describe and logs
alias kd='kubectl describe'
alias kl='kubectl logs'
alias klf='kubectl logs -f'

# Exec
alias ke='kubectl exec -it'

# Apply and delete
alias ka='kubectl apply -f'
alias kdel='kubectl delete'

# Context and namespace
alias kctx='kubectl config current-context'
alias kns='kubectl config set-context --current --namespace'
