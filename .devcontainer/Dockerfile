# Ruby 3.2 on Debian 12 (bookworm), maintained by Dev Containers
FROM mcr.microsoft.com/devcontainers/ruby:1-3.2-bookworm

# System deps for native gems + git/certs
USER root
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential curl git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Universal Ruby/Bundler env for the 'vscode' user
ENV GEM_HOME=/home/vscode/.gem \
    GEM_PATH=/home/vscode/.gem \
    BUNDLE_PATH=/home/vscode/.bundle \
    PATH=/home/vscode/.bundle/bin:/home/vscode/.gem/bin:$PATH

RUN mkdir -p /home/vscode/.gem /home/vscode/.bundle/bin \
 && chown -R vscode:vscode /home/vscode/.gem /home/vscode/.bundle

USER vscode
# Ensure bundler is present for postCreate
RUN gem update --system && gem install bundler
