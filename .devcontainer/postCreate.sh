#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.gem" "$HOME/.bundle/bin"

# Bundler to user path
bundle config set --global path "$HOME/.bundle"
bundle config set --global bin  "$HOME/.bundle/bin"
bundle config unset --global path.system || true

# Add to interactive shells too
grep -qxF 'export GEM_HOME="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_HOME="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export GEM_PATH="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_PATH="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export BUNDLE_PATH="$HOME/.bundle"' ~/.bashrc || echo 'export BUNDLE_PATH="$HOME/.bundle"' >> ~/.bashrc
grep -qxF 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' >> ~/.bashrc

# Ensure current shell has it now
export GEM_HOME="${GEM_HOME:-$HOME/.gem}"
export GEM_PATH="${GEM_PATH:-$HOME/.gem}"
export BUNDLE_PATH="${BUNDLE_PATH:-$HOME/.bundle}"
export PATH="$BUNDLE_PATH/bin:$GEM_HOME/bin:$PATH"

# Install gems (if Gemfile present)
if [ -f Gemfile ]; then
  bundle install
fi
