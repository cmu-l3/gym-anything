#!/bin/bash
set -e

echo "=== Installing TiddlyWiki ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Node.js 18.x LTS
apt-get install -y ca-certificates curl gnupg
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs

# Verify Node.js installation
node --version
npm --version

# Install TiddlyWiki globally
npm install -g tiddlywiki

# Verify TiddlyWiki installation
tiddlywiki --version

# Install GUI tools for automation and verification
apt-get install -y \
    wmctrl \
    xdotool \
    imagemagick \
    jq \
    python3-pip

# Install Firefox if not already installed
if ! command -v firefox &> /dev/null; then
    apt-get install -y firefox
fi

echo "=== TiddlyWiki installation complete ==="
