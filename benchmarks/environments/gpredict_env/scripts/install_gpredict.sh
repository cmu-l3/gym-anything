#!/bin/bash
set -e

echo "=== Installing GPredict and dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package manager
apt-get update

# Install GPredict
echo "Installing GPredict..."
apt-get install -y gpredict

# Install utility tools for UI automation and screenshots
echo "Installing utility tools..."
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    python3-pip \
    python3-dev \
    imagemagick \
    curl \
    wget

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== GPredict installation complete ==="
