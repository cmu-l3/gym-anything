#!/bin/bash
echo "=== Setting up Firefox Custom Root CA task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Install required tools (libnss3-tools for certutil)
export DEBIAN_FRONTEND=noninteractive
apt-get update -yq && apt-get install -yq libnss3-tools openssl python3

# Add local DNS resolution
if ! grep -q "internal.corp.local" /etc/hosts; then
    echo "127.0.0.1 internal.corp.local" >> /etc/hosts
fi

# =====================================================================
# PKI SETUP: Generate Root CA and Server Certificate
# =====================================================================
echo "Generating Corporate PKI..."
PKI_DIR="/tmp/pki"
mkdir -p "$PKI_DIR"

# 1. Generate Root CA
openssl req -x509 -sha256 -days 3650 -nodes -newkey rsa:2048 \
    -subj "/CN=Acme Corp Root CA/C=US/L=San Francisco" \
    -keyout "$PKI_DIR/rootCA.key" -out "/home/ga/Downloads/corporate_root_ca.crt"
chown ga:ga "/home/ga/Downloads/corporate_root_ca.crt"

# 2. Generate Server Private Key and CSR
openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$PKI_DIR/server.key" \
    -subj "/CN=internal.corp.local/C=US/L=San Francisco" \
    -out "$PKI_DIR/server.csr"

# 3. Create v3 extensions file for SAN (Subject Alternative Name - required by Firefox)
cat > "$PKI_DIR/v3.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = internal.corp.local
EOF

# 4. Sign Server Certificate with Root CA
openssl x509 -req -in "$PKI_DIR/server.csr" \
    -CA "/home/ga/Downloads/corporate_root_ca.crt" \
    -CAkey "$PKI_DIR/rootCA.key" -CAcreateserial \
    -out "$PKI_DIR/server.crt" -days 365 -sha256 -extfile "$PKI_DIR/v3.ext"

# =====================================================================
# INTRANET SERVER SETUP
# =====================================================================
echo "Setting up secure intranet server..."
WWW_DIR="/var/www/corp_intranet"
mkdir -p "$WWW_DIR"

cat > "$WWW_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Acme Corp - IT Policies</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; max-width: 800px; line-height: 1.6; }
        .header { background: #0044cc; color: white; padding: 20px; border-radius: 5px; }
        .content { margin-top: 20px; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Corporate IT Policy: Zero Trust Architecture</h1>
    </div>
    <div class="content">
        <p>Welcome to the secure internal intranet. This document outlines our transition to ZTA.</p>
        
        <h2 id="core-component">Tenets of Zero Trust</h2>
        
        <p>1. All data sources and computing services are considered resources.</p>
        <p>2. All communication is secured regardless of network location.</p>
        <p>3. Access to individual enterprise resources is granted on a per-session basis.</p>
        <p>4. Access to resources is determined by dynamic policy.</p>
    </div>
</body>
</html>
EOF

# Create Python HTTPS server script
cat > "/tmp/https_server.py" << EOF
import http.server
import ssl
import sys
import os

os.chdir('$WWW_DIR')
server_address = ('127.0.0.1', 8443)
httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(certfile='$PKI_DIR/server.crt', keyfile='$PKI_DIR/server.key')
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

print("Starting secure server on port 8443...")
httpd.serve_forever()
EOF

# Start the server in the background
nohup python3 /tmp/https_server.py > /tmp/https_server.log 2>&1 &
sleep 2

# =====================================================================
# FIREFOX SETUP
# =====================================================================
# Ensure clean Firefox profile cert overrides
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
mkdir -p "$PROFILE_DIR"
rm -f "$PROFILE_DIR/cert_override.txt"

# Start Firefox
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_firefox.sh &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="