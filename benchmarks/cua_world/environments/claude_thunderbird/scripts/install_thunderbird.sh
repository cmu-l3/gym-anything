#!/bin/bash
set -euo pipefail

echo "=== Installing Thunderbird and related packages ==="

# Update package manager
apt-get update

# Install required packages for adding PPAs
apt-get install -y \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg

# Remove snap-based Thunderbird if it exists (doesn't work in Docker)
echo "Removing snap-based Thunderbird stub..."
apt-get remove -y thunderbird 2>/dev/null || true

# Add Mozilla Team PPA for proper Thunderbird package (non-snap)
echo "Adding Mozilla Team PPA..."
add-apt-repository -y ppa:mozillateam/ppa

# Configure APT to prefer Mozilla Team PPA over snap
# This prevents Ubuntu from trying to install the snap version
cat > /etc/apt/preferences.d/mozilla-thunderbird << 'APTPREFEOF'
Package: thunderbird*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
APTPREFEOF

echo "Pinned Thunderbird to Mozilla Team PPA"

# Update after adding PPA
apt-get update

# Install Thunderbird email client from Mozilla PPA
echo "Installing Thunderbird from Mozilla Team PPA..."
apt-get install -y \
    thunderbird \
    thunderbird-locale-en \
    thunderbird-locale-en-us

# Install mail utilities for testing and verification
echo "Installing mail utilities..."
apt-get install -y \
    mailutils \
    s-nail \
    msmtp \
    msmtp-mta \
    bsd-mailx \
    mutt

# Install calendar/contacts utilities
echo "Installing calendar and contact utilities..."
apt-get install -y \
    libical-dev 

    # libvcard-perl \
    # vcf2ldif

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    xclip

# Install Python libraries for email/calendar parsing and verification
echo "Installing Python email/calendar libraries..."
pip3 install --no-cache-dir --break-system-packages \
    icalendar \
    vobject \
    python-dateutil \
    pytz \
    beautifulsoup4 \
    lxml \
    eml-parser

# Install file handling utilities
echo "Installing file utilities..."
apt-get install -y \
    unzip \
    zip \
    p7zip-full \
    rar \
    unrar

# Install image processing for email verification (logos, inline images)
echo "Installing image processing tools..."
apt-get install -y \
    imagemagick \
    graphicsmagick \
    poppler-utils

# Install fonts for better email rendering
echo "Installing additional fonts..."
apt-get install -y \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-noto-color-emoji \
    fonts-liberation2 \
    fonts-roboto \
    fonts-open-sans

# Install SQLite tools for database verification
echo "Installing SQLite tools..."
apt-get install -y \
    sqlite3 \
    sqlitebrowser

# Optional: Install local mail server for advanced testing
# Commented out by default - enable if tasks need full SMTP/IMAP
# echo "Installing local mail server (optional)..."
# apt-get install -y \
#     dovecot-core \
#     dovecot-imapd \
#     postfix \
#     mailutils

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Thunderbird installation completed ==="
