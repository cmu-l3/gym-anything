#!/bin/bash
echo "=== Setting up Webhook Notification Integration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST
rm -f /tmp/webhook_receipts.json 2>/dev/null || true
rm -f /tmp/webhook_notification_result.json 2>/dev/null || true
rm -f /tmp/webhook_server.log 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/webhook_notification_start_ts
echo "Task start recorded: $(cat /tmp/webhook_notification_start_ts)"

# Record initial command and telemetry counts for anti-gaming verification
INITIAL_CMDS=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
INITIAL_TLM=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
echo "Initial COLLECT command count: $INITIAL_CMDS"
echo "Initial COLLECTS telemetry count: $INITIAL_TLM"
printf '%s' "$INITIAL_CMDS" > /tmp/webhook_initial_cmds
printf '%s' "$INITIAL_TLM" > /tmp/webhook_initial_tlm

# Start the mock webhook server
echo "Starting mock webhook server on port 8080..."
cat > /tmp/mock_webhook.py << 'EOF'
import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            payload = json.loads(post_data.decode('utf-8'))
            payload['_timestamp'] = time.time()
            
            with open('/tmp/webhook_receipts.json', 'a') as f:
                f.write(json.dumps(payload) + '\n')
                
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        except Exception as e:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"error":"Bad Request"}')

    def log_message(self, format, *args):
        pass  # Suppress standard logging to keep it clean

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8080), WebhookHandler)
    server.serve_forever()
EOF

# Kill any existing server on port 8080
fuser -k 8080/tcp 2>/dev/null || true
sleep 1

# Run the webhook server in the background
nohup python3 /tmp/mock_webhook.py > /tmp/webhook_server.log 2>&1 &
echo "Mock webhook server running."

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/webhook_notification_start.png

echo "=== Webhook Notification Integration Setup Complete ==="
echo ""
echo "Task: Author an automation script to send commands and push alerts."
echo "Webhook URL: http://localhost:8080/alert"
echo ""