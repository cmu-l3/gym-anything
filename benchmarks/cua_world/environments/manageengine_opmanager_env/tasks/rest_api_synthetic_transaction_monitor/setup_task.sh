#!/bin/bash
# setup_task.sh — REST API Synthetic Transaction Monitor
# Starts a mock API service, waits for OpManager, and writes the spec file to the desktop.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up REST API Synthetic Transaction Monitor Task ==="

# ------------------------------------------------------------
# 1. Start the Mock API Service on port 9090
# ------------------------------------------------------------
echo "[setup] Starting local mock API service on port 9090..."
cat > /tmp/mock_api.py << 'EOF'
import http.server
import socketserver
import json
import logging
import sys

# Configure logging to write to our log file
logging.basicConfig(filename='/tmp/mock_api_requests.log', level=logging.INFO, format='%(asctime)s - %(message)s')

class MockAPIHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress default console logging
        pass

    def do_GET(self):
        logging.info(f"GET {self.path}")
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status": "Mock API is running"}')

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        
        logging.info(f"POST {self.path} PAYLOAD:{post_data}")
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        if self.path == '/api/checkout':
            self.wfile.write(b'{"status": "checkout_operational", "code": 200}')
        else:
            self.wfile.write(b'{"status": "unknown_endpoint", "code": 404}')

with socketserver.TCPServer(("", 9090), MockAPIHandler) as httpd:
    print("Serving mock API on port 9090")
    httpd.serve_forever()
EOF

# Ensure log file exists with right permissions
touch /tmp/mock_api_requests.log
chmod 666 /tmp/mock_api_requests.log

# Kill any existing process on 9090 and start the mock API
fuser -k 9090/tcp 2>/dev/null || true
nohup python3 /tmp/mock_api.py > /tmp/mock_api_console.log 2>&1 &
echo $! > /tmp/mock_api.pid

# Wait for mock API to come up
for i in {1..10}; do
    if curl -s http://localhost:9090/ > /dev/null; then
        echo "[setup] Mock API is responding."
        break
    fi
    sleep 1
done

# ------------------------------------------------------------
# 2. Wait for OpManager to be ready
# ------------------------------------------------------------
echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 3. Write API Monitoring spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/api_monitoring_spec.txt" << 'SPEC_EOF'
API Synthetic Monitoring Specification
Version: 1.0
Author: SRE Team

We need to ensure our internal checkout microservice is responding correctly to API requests, not just accepting network connections.

Please create a new URL Monitor in OpManager with the following configuration:

1. Basic Settings:
   - Monitor Name: Checkout-API-Health
   - URL: http://localhost:9090/api/checkout
   - Polling Interval: 5 minutes

2. Advanced HTTP Settings (Required for API transaction testing):
   - HTTP Method / Request Type: POST
   - Request Payload / Body: {"action":"ping"}
   - Match String / Search Content: checkout_operational

Note: The advanced HTTP settings (Method, Payload, Match String) are critical. If the monitor only performs a GET request, it will not test the database backend of the checkout service.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/api_monitoring_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Spec file written to $DESKTOP_DIR/api_monitoring_spec.txt"

# ------------------------------------------------------------
# 4. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/api_monitor_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/api_monitor_setup_screenshot.png" || true

echo "[setup] === REST API Synthetic Transaction Monitor Task Setup Complete ==="