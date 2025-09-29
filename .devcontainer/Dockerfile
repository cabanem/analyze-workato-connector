# Ruby 3.1 is supported by the Workato Connector SDK; pin 3.1.7 for stability.
FROM mcr.microsoft.com/devcontainers/ruby:3.1.7

SHELL ["/bin/bash", "-lc"]

# System deps: build toolchain, ICU (for charlock_holmes), Graphviz (for DOT)
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    pkg-config \
    libicu-dev \
    graphviz \
  && rm -rf /var/lib/apt/lists/*

# RubyGems & Bundler
RUN gem update --system \
  && gem install bundler

# Optional global tools to make life easier inside the devcontainer
# - workato-connector-sdk CLI for quick sanity checks
# - parser pinned to a modern series compatible with Ruby 3.1.x
RUN gem install workato-connector-sdk \
  && gem install parser -v "~> 3.3"

# Locale/env niceties
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Default workdir (devcontainers already sets this, but be explicit)
WORKDIR /workspaces
