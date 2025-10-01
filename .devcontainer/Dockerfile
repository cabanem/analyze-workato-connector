# Base Ubuntu + devcontainers features are great, but we want a deterministic layer
# that includes build tools for native gems and a universal Ruby/Bundler env.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# ---- System deps for Ruby native gems like 'parser' (and others) ----
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    curl \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# ---- Install Ruby 3.2 via devcontainers feature ----
# Using the published feature directly in Dockerfile for deterministic builds
# (same feature you used in devcontainer.json). Pin to 3.2.
ARG USERNAME=vscode
ARG RUNTIME_DIR=/usr/local
RUN curl -fsSL https://raw.githubusercontent.com/devcontainers/features/main/script-library/ruby-debian.sh -o /tmp/ruby-debian.sh \
  && /bin/bash /tmp/ruby-debian.sh "3.2" "false" \
  && rm /tmp/ruby-debian.sh

# ---- Universal Ruby/Bundler env for the vscode user ----
ENV GEM_HOME=/home/${USERNAME}/.gem \
    GEM_PATH=/home/${USERNAME}/.gem \
    BUNDLE_PATH=/home/${USERNAME}/.bundle \
    PATH=/home/${USERNAME}/.bundle/bin:/home/${USERNAME}/.gem/bin:$PATH

RUN mkdir -p /home/${USERNAME}/.gem /home/${USERNAME}/.bundle/bin \
  && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.gem /home/${USERNAME}/.bundle

# ---- Update RubyGems & install Bundler (as user) ----
USER ${USERNAME}
RUN gem update --system && gem install bundler

# Back to root only if you need more system-level steps later
USER root
