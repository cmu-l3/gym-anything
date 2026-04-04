#!/bin/bash
set -euo pipefail

echo "=== Installing Wireshark and dependencies ==="

# Configure faster APT mirrors
echo "Configuring APT settings..."
cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
Acquire::Retries "3";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::ftp::Timeout "10";
Acquire::Queue-Mode "access";
Acquire::http::No-Cache "false";
APT_CONF_EOF

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Pre-seed the wireshark debconf question to avoid interactive prompt
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

# Update package lists
apt-get update -q

# Install Wireshark (GUI), tshark (CLI), and capture tools
echo "Installing Wireshark and tshark..."
apt-get install -y -q \
    wireshark \
    tshark \
    tcpdump

# Install GUI automation and screenshot tools
echo "Installing GUI automation tools..."
apt-get install -y -q \
    xdotool \
    wmctrl \
    scrot \
    x11-utils

# Install Python tools for verification
echo "Installing Python verification tools..."
apt-get install -y -q \
    python3-pip \
    python3-dev

# Install additional network utilities for generating test traffic
echo "Installing network utilities..."
apt-get install -y -q \
    wget \
    curl \
    net-tools \
    dnsutils \
    iputils-ping

# Add ga user to wireshark group so they can capture packets without root
usermod -aG wireshark ga 2>/dev/null || true

# Create directories for PCAP data
mkdir -p /home/ga/Documents/captures
mkdir -p /home/ga/Desktop

# Download helper: tries multiple URLs, verifies non-zero file
download_pcap() {
    local dest="$1"
    shift
    for url in "$@"; do
        wget -q --timeout=30 -O "$dest" "$url" 2>/dev/null
        if [ -s "$dest" ]; then
            return 0
        fi
        rm -f "$dest"
    done
    echo "ERROR: Failed to download $(basename "$dest") from all URLs"
    return 1
}

echo "Downloading official Wireshark sample PCAP files..."

download_pcap /home/ga/Documents/captures/http.cap \
    "https://wiki.wireshark.org/uploads/27707187aeb30df68e70c8fb9d614981/http.cap" \
    "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/27707187aeb30df68e70c8fb9d614981/http.cap" \
    "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/http.cap"

download_pcap /home/ga/Documents/captures/dns.cap \
    "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/dns.cap" \
    "https://wiki.wireshark.org/uploads/4f09f1d01a6fbec4b1ae0a8f6b3360e2/dns.cap" \
    "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/4f09f1d01a6fbec4b1ae0a8f6b3360e2/dns.cap"

download_pcap /home/ga/Documents/captures/telnet-cooked.pcap \
    "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/telnet-cooked.pcap" \
    "https://wiki.wireshark.org/uploads/db0c22aeab36db4a3213a8012a5b5b84/telnet-cooked.pcap" \
    "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/db0c22aeab36db4a3213a8012a5b5b84/telnet-cooked.pcap"

download_pcap /home/ga/Documents/captures/200722_tcp_anon.pcapng \
    "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/200722_tcp_anon.pcapng" \
    "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" \
    "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng"

download_pcap /home/ga/Documents/captures/smtp.pcap \
    "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/smtp.pcap" \
    "https://wiki.wireshark.org/uploads/05c0eb3fd99c42cd0cdba48cce5c596a/smtp.pcap" \
    "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/05c0eb3fd99c42cd0cdba48cce5c596a/smtp.pcap"

# Set ownership and permissions (directories need 755, files need 644)
chown -R ga:ga /home/ga/Documents/captures/
find /home/ga/Documents/captures/ -type d -exec chmod 755 {} \;
find /home/ga/Documents/captures/ -type f -exec chmod 644 {} \;

# Verify downloads - check for missing or 0-byte files
echo "=== Verifying downloaded PCAP files ==="
DOWNLOAD_FAILURES=0
for f in http.cap dns.cap smtp.pcap telnet-cooked.pcap 200722_tcp_anon.pcapng; do
    FULL_PATH="/home/ga/Documents/captures/$f"
    if [ ! -s "$FULL_PATH" ]; then
        echo "  ERROR: $f is missing or empty!"
        DOWNLOAD_FAILURES=$((DOWNLOAD_FAILURES + 1))
    else
        SIZE=$(stat -c%s "$FULL_PATH" 2>/dev/null || echo "0")
        echo "  $FULL_PATH: $SIZE bytes"
    fi
done

if [ "$DOWNLOAD_FAILURES" -gt 0 ]; then
    echo "WARNING: $DOWNLOAD_FAILURES PCAP file(s) failed to download"
fi

echo "=== Wireshark installation complete ==="
