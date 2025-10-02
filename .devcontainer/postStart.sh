#!/usr/bin/env bash
set -euo pipefail

export GEM_HOME="${GEM_HOME:-$HOME/.gem}"
export GEM_PATH="${GEM_PATH:-$HOME/.gem}"
export BUNDLE_PATH="${BUNDLE_PATH:-$HOME/.bundle}"
export PATH="$BUNDLE_PATH/bin:$GEM_HOME/bin:$PATH"

if [ -f Gemfile ]; then
  bundle check || bundle install
fi
