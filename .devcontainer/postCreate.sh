#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.gem" "$HOME/.bundle/bin"

# Bundler to user path
bundle config set --global path "$HOME/.bundle"
bundle config set --global bin  "$HOME/.bundle/bin"
bundle config unset --global path.system || true

# RubyGems to user path
grep -qxF 'export GEM_HOME="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_HOME="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export GEM_PATH="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_PATH="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' >> ~/.bashrc

# Make sure the current shell picks it up for the initial install
# (non-interactive shells don’t always source .bashrc)
export GEM_HOME="$HOME/.gem"
export GEM_PATH="$HOME/.gem"
export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"

# Install project gems if a Gemfile exists
if [ -f Gemfile ]; then
  bundle install
fi
