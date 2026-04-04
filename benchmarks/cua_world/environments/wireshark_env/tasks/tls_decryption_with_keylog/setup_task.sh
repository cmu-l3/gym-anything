#!/bin/bash
set -e

echo "=== Setting up TLS Decryption Task ==="

# directories
CAPTURE_DIR="/home/ga/Documents/captures"
GROUND_TRUTH_DIR="/var/lib/app/ground_truth"
mkdir -p "$CAPTURE_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# 1. Generate a random secret UUID for this run
SECRET_UUID=$(cat /proc/sys/kernel/random/uuid)
echo "$SECRET_UUID" > "$GROUND_TRUTH_DIR/secret_uuid.txt"
chmod 600 "$GROUND_TRUTH_DIR/secret_uuid.txt" # Hide from agent
echo "Generated Secret: $SECRET_UUID"

# 2. Create Python script to generate traffic
cat > /tmp/generate_traffic.py << 'EOF'
import http.server
import ssl
import sys
import os
import threading
import time

PORT = 4443
CERT_FILE = "/tmp/cert.pem"
KEY_FILE = "/tmp/key.pem"
SECRET_UUID = sys.argv[1]

class SecretHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        # Write the secret flag to the body
        response = f"Welcome to the Secure API.\nSECRET_FLAG: {SECRET_UUID}\nEnd of transmission.\n"
        self.wfile.write(response.encode('utf-8'))
    
    def log_message(self, format, *args):
        return  # Suppress console logging

def run_server():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT_FILE, KEY_FILE)
    
    server_address = ('localhost', PORT)
    httpd = http.server.HTTPServer(server_address, SecretHandler)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    httpd.serve_forever()

if __name__ == "__main__":
    run_server()
EOF

# 3. Generate Self-Signed Certificate
echo "Generating SSL certificates..."
openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /tmp/cert.pem -days 1 -nodes -subj "/C=US/ST=State/L=City/O=Company/CN=localhost" 2>/dev/null

# 4. Start the Python HTTPS Server in background
echo "Starting HTTPS server..."
python3 /tmp/generate_traffic.py "$SECRET_UUID" &
SERVER_PID=$!
sleep 2 # Give it time to bind

# 5. Start Packet Capture (tcpdump)
echo "Starting packet capture..."
# Capture on loopback, port 4443
tcpdump -i lo -w "$CAPTURE_DIR/secure_api.pcap" port 4443 &
TCPDUMP_PID=$!
sleep 2

# 6. Generate Traffic with curl (Client)
# IMPORTANT: Export SSLKEYLOGFILE to capture session keys
echo "Generating client traffic..."
export SSLKEYLOGFILE="$CAPTURE_DIR/session_keys.log"

# Make the request (insecure to accept self-signed cert)
curl -k https://localhost:4443/api/v1/secret > /dev/null 2>&1 || true

sleep 2

# 7. Cleanup
echo "Stopping capture and server..."
kill $TCPDUMP_PID || true
kill $SERVER_PID || true
wait $TCPDUMP_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

# 8. Set permissions
chown ga:ga "$CAPTURE_DIR/secure_api.pcap"
chown ga:ga "$CAPTURE_DIR/session_keys.log"
chmod 644 "$CAPTURE_DIR/secure_api.pcap"
chmod 644 "$CAPTURE_DIR/session_keys.log"

# 9. Clean up temp files
rm -f /tmp/cert.pem /tmp/key.pem /tmp/generate_traffic.py

# 10. Launch Wireshark
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark &"
    sleep 5
fi

# Maximize Wireshark
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
echo "Capturing initial state..."
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="