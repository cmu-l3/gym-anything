#!/bin/bash
# setup_task.sh for securedrop_onion_submission_workflow
# Prepares a local Tor HiddenService acting as a mock SecureDrop portal.

set -e
echo "=== Setting up SecureDrop workflow task ==="

# Record task start timestamp for verification
date +%s > /tmp/task_start_time.txt

# Safely install required packages
wait_for_apt() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    echo "Waiting for apt lock..."
    sleep 2
  done
}

echo "Installing required packages..."
wait_for_apt
sudo DEBIAN_FRONTEND=noninteractive apt-get update -yq
wait_for_apt
sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq tor python3 curl

# 1. Generate GPG keypair for the mock server
echo "Generating GPG key for SecureDrop mock..."
mkdir -p /tmp/securedrop_mock
chmod 700 /tmp/securedrop_mock
export GNUPGHOME=/tmp/securedrop_mock

cat > /tmp/gen-key-script <<EOF
%echo Generating a standard key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: SecureDrop Mock
Name-Email: secure@drop.local
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
gpg --batch --gen-key /tmp/gen-key-script
gpg --armor --export secure@drop.local > /tmp/securedrop_mock/public.key

# 2. Start Python mock server
echo "Starting mock SecureDrop web server..."
cat > /tmp/mock_securedrop.py <<'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import os

PUB_KEY = open('/tmp/securedrop_mock/public.key').read()

HTML = f"""
<html>
<head><title>SecureDrop Mock</title></head>
<body>
    <h1>Submit a Tip</h1>
    <p>Use our PGP key to encrypt your file:</p>
    <pre>{PUB_KEY}</pre>
    <form method="POST" action="/submit">
        <textarea name="tip" rows="20" cols="80"></textarea><br>
        <input type="submit" value="Submit">
    </form>
</body>
</html>
"""

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(HTML.encode('utf-8'))

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        parsed = urllib.parse.parse_qs(post_data)
        
        os.makedirs('/tmp/securedrop_submissions', exist_ok=True)
        if 'tip' in parsed:
            import time
            with open(f'/tmp/securedrop_submissions/sub_{int(time.time())}.txt', 'w') as f:
                f.write(parsed['tip'][0])
                
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(b"<html><body><h1>Submission Received</h1><p>Thank you.</p></body></html>")

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

nohup python3 /tmp/mock_securedrop.py > /tmp/mock_server.log 2>&1 &

# 3. Setup and restart Tor to publish the HiddenService
echo "Configuring Tor HiddenService..."
sudo bash -c 'cat > /etc/tor/torrc <<EOF
SocksPort 9050
HiddenServiceDir /var/lib/tor/securedrop/
HiddenServicePort 80 127.0.0.1:8080
EOF'

sudo systemctl restart tor || sudo -u debian-tor tor -f /etc/tor/torrc > /tmp/tor_sys.log 2>&1 &

echo "Waiting for HiddenService descriptor..."
for i in {1..30}; do
    if sudo test -f /var/lib/tor/securedrop/hostname; then
        break
    fi
    sleep 1
done

ONION_URL=$(sudo cat /var/lib/tor/securedrop/hostname 2>/dev/null || echo "")
if [ -z "$ONION_URL" ]; then
    echo "ERROR: Failed to create HiddenService!"
    exit 1
fi

echo "http://$ONION_URL" > /home/ga/Desktop/securedrop_address.txt
chown ga:ga /home/ga/Desktop/securedrop_address.txt

echo "Waiting for HiddenService to be reachable on the Tor network (this takes ~30-60s)..."
for i in {1..120}; do
    if curl -x socks5h://127.0.0.1:9050 -s "http://$ONION_URL" | grep -q "SecureDrop Mock"; then
        echo "Hidden service is now reachable!"
        break
    fi
    sleep 5
done

# 4. Prepare Evidence File
mkdir -p /home/ga/Documents
echo "CONFIDENTIAL: The CEO is embezzling funds through offshore accounts in the Cayman Islands. Project X is a coverup." > /home/ga/Documents/evidence_tip.txt
chown -R ga:ga /home/ga/Documents

# 5. Launch Tor Browser
echo "Launching Tor Browser..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        break
    fi
done

if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for window and maximize
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="