# Ruby 3.2 on Ubuntu 24.04 (noble), maintained by devcontainers
FROM mcr.microsoft.com/devcontainers/ruby:1-3.2-noble

# System deps for native gems (e.g., parser) + git/certs
USER root
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential curl git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Universal Ruby/Bundler env for the vscode user
ENV GEM_HOME=/home/vscode/.gem \
    GEM_PATH=/home/vscode/.gem \
    BUNDLE_PATH=/home/vscode/.bundle \
    PATH=/home/vscode/.bundle/bin:/home/vscode/.gem/bin:$PATH

RUN mkdir -p /home/vscode/.gem /home/vscode/.bundle/bin \
 && chown -R vscode:vscode /home/vscode/.gem /home/vscode/.bundle

USER vscode
RUN gem update --system && gem install bundler
