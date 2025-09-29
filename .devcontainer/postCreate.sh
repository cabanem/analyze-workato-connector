#!/usr/bin/env bash
set -euo pipefail

# --- Paths for user-local gems & bundler ---
mkdir -p "$HOME/.gem" "$HOME/.bundle/bin"

# Bundler config to vendor into home (keeps container clean & reproducible)
bundle config set --global path "$HOME/.bundle"
bundle config set --global bin  "$HOME/.bundle/bin"
# Ensure we do not leak into system gems path
bundle config unset --global path.system || true

# Shell PATH env for current and future sessions
grep -qxF 'export GEM_HOME="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_HOME="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export GEM_PATH="$HOME/.gem"'  ~/.bashrc || echo 'export GEM_PATH="$HOME/.gem"'  >> ~/.bashrc
grep -qxF 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"' >> ~/.bashrc

# Apply to current (non-interactive) shell as well
export GEM_HOME="$HOME/.gem"
export GEM_PATH="$HOME/.gem"
export PATH="$HOME/.bundle/bin:$HOME/.gem/bin:$PATH"

# --- Ensure a compatible parser is available via Bundler (project-local) ---
# If no Gemfile, create a minimal one that pins 'parser' to a version
# compatible with Ruby 3.1.x and requires parser/current.
if [ ! -f Gemfile ]; then
  cat > Gemfile <<'GEMFILE'
source "https://rubygems.org"

ruby "~> 3.1.7"

gem "parser", "~> 3.3", require: "parser/current"
# Add anything else you need:
# gem "rake"
# gem "rubocop"
GEMFILE
fi

# Install project gems
bundle install --jobs 4 --retry 3

# --- Developer QoL: print versions to help debugging env mismatches ---
echo "== Toolchain versions =="
echo "Ruby:     $(ruby -v)"
echo "Bundler:  $(bundle -v)"
echo "Parser:   $(ruby -e 'require \"parser/current\"; puts Parser::VERSION rescue puts \"(unknown)\"')"
echo "SDK CLI:  $(workato version || echo 'workato not found')"
echo "Graphviz: $(dot -V 2>&1 | head -n1 || true)"
echo "========================"

# Optional: create a bin alias for running analyzer with bundler
mkdir -p bin
cat > bin/analyze <<'BIN'
#!/usr/bin/env bash
set -euo pipefail
exec bundle exec ruby analyze/analyze_0.2.0.rb "$@"
BIN
chmod +x bin/analyze
