#!/bin/bash
# setup_task.sh - Setup for Legacy Portal Access task
set -e

echo "=== Setting up Legacy Portal Access Task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill existing processes
echo "Killing existing Edge and Python instances..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
pkill -f "legacy_server.py" 2>/dev/null || true
sleep 2

# 2. Generate Ground Truth Data
SECRET_CODE="MFST-$(shuf -i 1000-9999 -n 1)-$(date +%s | tail -c 4)"
GROUND_TRUTH_DIR="/var/lib/legacy_portal"
mkdir -p "$GROUND_TRUTH_DIR"
echo "$SECRET_CODE" > "$GROUND_TRUTH_DIR/secret_code.txt"
chmod 644 "$GROUND_TRUTH_DIR/secret_code.txt"

# Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create the Legacy Server Script
SERVER_SCRIPT="/tmp/legacy_server.py"
cat > "$SERVER_SCRIPT" << EOF
import http.server
import socketserver
import sys

PORT = 8000
SECRET_CODE = "$SECRET_CODE"

class LegacyRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        user_agent = self.headers.get('User-Agent', '')
        
        # Log the access attempt for verification
        with open('/tmp/server_access.log', 'a') as log:
            log.write(f"UA: {user_agent}\n")

        # Check for IE signatures
        if "MSIE" in user_agent or "Trident" in user_agent:
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = f"""
            <html>
            <head><title>OldPort Logistics Portal</title></head>
            <body style="background-color: #e0e0e0; font-family: 'Times New Roman', serif;">
                <div style="width: 600px; margin: 50px auto; border: 2px solid darkblue; padding: 20px; background: white;">
                    <h1 style="color: darkblue;">OldPort Logistics Intranet</h1>
                    <p><strong>Welcome, Authorized User.</strong></p>
                    <hr>
                    <p>System Status: <span style="color: green;">ONLINE</span></p>
                    <div style="background-color: #ffffcc; padding: 15px; border: 1px solid #999;">
                        <h3>Today's Manifest Code:</h3>
                        <h2 style="font-family: monospace; font-size: 24px;">{SECRET_CODE}</h2>
                        <p style="font-size: small;">Valid until 23:59 Server Time</p>
                    </div>
                </div>
            </body>
            </html>
            """
            self.wfile.write(html.encode('utf-8'))
        else:
            self.send_response(403)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = """
            <html>
            <head><title>Access Denied</title></head>
            <body style="background-color: #ffcccc; font-family: sans-serif; text-align: center; padding-top: 50px;">
                <div style="border: 2px solid red; display: inline-block; padding: 20px; background: white;">
                    <h1 style="color: red;">ERROR 403: Browser Not Supported</h1>
                    <p>This legacy system requires <strong>Internet Explorer</strong>.</p>
                    <p>Your browser is not recognized as a supported client.</p>
                    <p><em>Please contact IT Support if you believe this is an error.</em></p>
                </div>
            </body>
            </html>
            """
            self.wfile.write(html.encode('utf-8'))

    def log_message(self, format, *args):
        return  # Suppress default console logging

Handler = LegacyRequestHandler
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Serving at port {PORT}")
    httpd.serve_forever()
EOF

# 4. Start the Server in Background
echo "Starting legacy server..."
nohup python3 "$SERVER_SCRIPT" > /tmp/server_stdout.log 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > /tmp/server_pid.txt
sleep 2

# Verify server is up
if ! curl -s http://localhost:8000 > /dev/null; then
    echo "ERROR: Server failed to start."
    exit 1
fi

# 5. Launch Edge (Initial State)
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    http://localhost:8000 \
    > /tmp/edge.log 2>&1 &"

# Wait for Edge window
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# Capture initial screenshot (Should show Access Denied)
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Secret Code generated: $SECRET_CODE"