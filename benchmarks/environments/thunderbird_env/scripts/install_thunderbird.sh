#!/bin/bash
set -e

echo "=== Installing Mozilla Thunderbird ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Thunderbird and dependencies
apt-get install -y \
    thunderbird \
    xdotool \
    wmctrl \
    scrot \
    python3-pip \
    python3-venv \
    jq \
    sqlite3

# Verify installation
thunderbird --version || echo "Thunderbird installed (version check may not work headless)"
which thunderbird && echo "Thunderbird binary found at: $(which thunderbird)"

echo "=== Mozilla Thunderbird installation complete ==="
