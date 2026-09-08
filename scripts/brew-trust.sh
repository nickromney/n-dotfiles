#!/usr/bin/env bash
set -euo pipefail

# Keep Homebrew's trust policy explicit for the non-official entries managed by
# Brewfile. This replaces the deprecated HOMEBREW_NO_REQUIRE_TAP_TRUST escape.

trusted_formulas=(
  azure/functions/azure-functions-core-tools@4
  dicklesworthstone/tap/ubs
  modem-dev/tap/hunk
  noahgorstein/tap/jqp
)

trusted_casks=(
  goreleaser/tap/goreleaser
  nikitabobko/tap/aerospace
)

for formula in "${trusted_formulas[@]}"; do
  brew trust --quiet --formula "$formula"
done

for cask in "${trusted_casks[@]}"; do
  brew trust --quiet --cask "$cask"
done
