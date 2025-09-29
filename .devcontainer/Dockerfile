# Ruby 3.1 is supported by the SDK. (Supported: 2.7.x, 3.0.x, 3.1.x)
FROM mcr.microsoft.com/devcontainers/ruby:3.1.7

# Build tools + ICU for charlock_holmes
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential pkg-config libicu-dev \
 && rm -rf /var/lib/apt/lists/*

# Ruby toolchain and SDK CLI
RUN gem update --system && gem install bundler workato-connector-sdk
