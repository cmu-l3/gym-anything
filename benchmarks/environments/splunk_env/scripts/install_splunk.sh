#!/bin/bash
set -e

echo "=== Installing Splunk Enterprise ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install dependencies
apt-get install -y \
    wget \
    curl \
    jq \
    p7zip-full \
    firefox \
    wmctrl \
    xdotool \
    xclip \
    scrot \
    imagemagick \
    python3-pip \
    python3-requests

# Download Splunk Enterprise
echo "=== Downloading Splunk Enterprise ==="
SPLUNK_DEB="/tmp/splunk.deb"
wget -O "$SPLUNK_DEB" "https://download.splunk.com/products/splunk/releases/9.4.0/linux/splunk-9.4.0-6b4ebe426ca6-linux-amd64.deb"

# Install Splunk
echo "=== Installing Splunk package ==="
dpkg -i "$SPLUNK_DEB"
rm -f "$SPLUNK_DEB"

# Pre-seed admin credentials
mkdir -p /opt/splunk/etc/system/local
cat > /opt/splunk/etc/system/local/user-seed.conf << 'EOF'
[user_info]
USERNAME = admin
PASSWORD = SplunkAdmin1!
EOF

# Configure web.conf for HTTP (no HTTPS redirect)
cat > /opt/splunk/etc/system/local/web.conf << 'EOF'
[settings]
httpport = 8000
enableSplunkWebSSL = false
EOF

# Set ownership
chown -R root:root /opt/splunk

echo "=== Downloading real-world log data ==="

# Disable exit-on-error for data downloads (best effort)
set +e

# Create data directories
mkdir -p /opt/splunk_data/{tutorial,security,syslog,apache}

# Helper: download file with retry and size validation
download_file() {
    local url="$1"
    local dest="$2"
    local min_size="${3:-1000}"  # minimum valid file size in bytes

    echo "Downloading: $url"
    wget --timeout=120 --tries=3 -O "$dest" "$url" 2>&1

    if [ -f "$dest" ]; then
        local size
        size=$(stat -c%s "$dest" 2>/dev/null || echo "0")
        if [ "$size" -lt "$min_size" ]; then
            echo "WARNING: Downloaded file too small ($size bytes), likely failed"
            rm -f "$dest"
            return 1
        fi
        echo "Downloaded successfully: $dest ($size bytes)"
        return 0
    fi
    echo "WARNING: Download failed for $url"
    return 1
}

# Download Splunk tutorial data (Buttercup Games - real web/auth/vendor logs)
if download_file "https://docs.splunk.com/images/Tutorial/tutorialdata.zip" "/tmp/tutorialdata.zip" 10000; then
    cd /opt/splunk_data/tutorial
    unzip -o /tmp/tutorialdata.zip && echo "Tutorial data extracted"
    rm -f /tmp/tutorialdata.zip
fi

# Download real auth.log data (SecRepo - real failed SSH attempts, CC BY 4.0)
if download_file "http://www.secrepo.com/auth.log/auth.log.gz" "/tmp/auth.log.gz" 1000; then
    gunzip -f /tmp/auth.log.gz
    mv /tmp/auth.log /opt/splunk_data/security/auth.log 2>/dev/null
    echo "Auth.log data extracted"
fi

# Download real Linux syslog data (Loghub project - real system logs, Zenodo)
if download_file "https://zenodo.org/records/8196385/files/Linux.tar.gz?download=1" "/tmp/Linux.tar.gz" 1000; then
    cd /opt/splunk_data/syslog
    tar xzf /tmp/Linux.tar.gz && echo "Linux syslog data extracted"
    rm -f /tmp/Linux.tar.gz
fi

# Download real SSH logs (Loghub project - real OpenSSH server logs)
if download_file "https://zenodo.org/records/8196385/files/SSH.tar.gz?download=1" "/tmp/SSH.tar.gz" 1000; then
    cd /opt/splunk_data/security
    tar xzf /tmp/SSH.tar.gz && echo "SSH log data extracted"
    rm -f /tmp/SSH.tar.gz
fi

# Download Apache error logs (Loghub - real Apache server logs)
if download_file "https://zenodo.org/records/8196385/files/Apache.tar.gz?download=1" "/tmp/Apache.tar.gz" 1000; then
    cd /opt/splunk_data/apache
    tar xzf /tmp/Apache.tar.gz && echo "Apache log data extracted"
    rm -f /tmp/Apache.tar.gz
fi

# Fallback: generate real system log data if downloads failed
DATA_FILE_COUNT=$(find /opt/splunk_data -type f -name "*.log" -o -name "*.csv" -o -name "*.txt" | wc -l)
echo "Downloaded data files: $DATA_FILE_COUNT"

if [ "$DATA_FILE_COUNT" -lt 2 ]; then
    echo "=== Fallback: Capturing real system logs from this VM ==="
    # Copy real system logs from the running VM as fallback data
    cp /var/log/syslog /opt/splunk_data/syslog/vm_syslog.log 2>/dev/null || true
    cp /var/log/auth.log /opt/splunk_data/security/vm_auth.log 2>/dev/null || true
    cp /var/log/kern.log /opt/splunk_data/syslog/vm_kern.log 2>/dev/null || true
    cp /var/log/dpkg.log /opt/splunk_data/syslog/vm_dpkg.log 2>/dev/null || true

    # Generate realistic Apache-style access log from the install activity
    cat > /opt/splunk_data/apache/access.log << 'ACCESSEOF'
192.168.1.100 - admin [27/Jan/2026:10:15:23 +0000] "GET /en-US/app/launcher/home HTTP/1.1" 200 8523 "-" "Mozilla/5.0"
192.168.1.100 - admin [27/Jan/2026:10:15:24 +0000] "GET /en-US/static/build/pages/enterprise/launcher.js HTTP/1.1" 200 145234 "http://localhost:8000/en-US/app/launcher/home" "Mozilla/5.0"
192.168.1.105 - - [27/Jan/2026:10:16:01 +0000] "GET /en-US/account/login HTTP/1.1" 200 4521 "-" "Mozilla/5.0"
192.168.1.105 - - [27/Jan/2026:10:16:15 +0000] "POST /en-US/account/login HTTP/1.1" 303 0 "http://localhost:8000/en-US/account/login" "Mozilla/5.0"
10.0.0.50 - - [27/Jan/2026:10:17:30 +0000] "GET /en-US/account/login HTTP/1.1" 200 4521 "-" "python-requests/2.28.0"
10.0.0.50 - - [27/Jan/2026:10:17:31 +0000] "POST /en-US/account/login HTTP/1.1" 401 1234 "-" "python-requests/2.28.0"
10.0.0.50 - - [27/Jan/2026:10:17:32 +0000] "POST /en-US/account/login HTTP/1.1" 401 1234 "-" "python-requests/2.28.0"
10.0.0.50 - - [27/Jan/2026:10:17:33 +0000] "POST /en-US/account/login HTTP/1.1" 401 1234 "-" "python-requests/2.28.0"
ACCESSEOF
    echo "Fallback data generated"
fi

# Re-enable exit-on-error
set -e

# Set permissions on data directory
chmod -R 755 /opt/splunk_data

echo "=== Splunk Enterprise installation complete ==="
echo "Data directories:"
find /opt/splunk_data -type f | head -30
