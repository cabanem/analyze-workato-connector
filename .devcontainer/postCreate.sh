#!/usr/bin/env bash
set -euo pipefail

# Universal, non-interactive friendly env
mkdir -p "$HOME/.gem" "$HOME/.bundle/bin"

# Bundler config to user path (no system mutation)
bundle config set --global path "$HOME/.bundle"
bundle config set --global bin  "$HOME/.bundle/bin"
bundle config unset --global path.system || true

# Also add for interactive shells
grep -qxF 'export GEM_HOME="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_HOME="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export GEM_PATH="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_PATH="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export BUNDLE_PATH="$HOME/.bundle"' ~/.bashrc || echo 'export BUNDLE_PATH="$HOME/.bundle"' >> ~/.bashrc
grep -qxF 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' >> ~/.bashrc

# Make sure current shell has it right now
export GEM_HOME="${GEM_HOME:-$HOME/.gem}"
export GEM_PATH="${GEM_PATH:-$HOME/.gem}"
export BUNDLE_PATH="${BUNDLE_PATH:-$HOME/.bundle}"
export PATH="$BUNDLE_PATH/bin:$GEM_HOME/bin:$PATH"

# Install project gems if present
if [ -f Gemfile ]; then
  bundle install
fi
