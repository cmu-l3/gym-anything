#!/bin/bash
echo "=== Setting up HTTP Sender Patient Notification Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare sample HL7 message
echo "Creating sample HL7 message..."
# Note: MLLP framing (\x0b ... \x1c\x0d) is usually handled by the sender tool, 
# but we'll save the raw content for 'cat'. 
# For 'nc', we need to ensure the file has the correct line endings (\r).
cat > /home/ga/sample_adt.hl7 << 'EOF'
MSH|^~\&|EPIC|MYHOSPITAL|PATIENTAPI|EXTERNAL|20240115143025||ADT^A01^ADT_A01|MSGID20240115001|P|2.5.1|||AL|NE
EVN|A01|20240115143025
PID|1||PAT78432^^^MYHOSPITAL^MR||MARTINEZ^ELENA^R||19780622|F|||456 OAK AVE^^SPRINGFIELD^IL^62704^US||2175551234|||||||SSN987654321
PV1|1|I|MED^302^B|U|||ATT54321^JOHNSON^PATRICIA|||INT||||||||VN20240115001|||||||||||||||||||||||||20240115143025
EOF
# Convert newlines to CR for HL7 standard
unix2dos /home/ga/sample_adt.hl7 2>/dev/null || sed -i 's/$/\r/' /home/ga/sample_adt.hl7
# Wrap in MLLP bytes for easy netcatting: Start Block (0x0b) + Data + End Block (0x1c) + CR (0x0d)
printf "\x0b" > /home/ga/sample_adt_mllp.hl7
cat /home/ga/sample_adt.hl7 >> /home/ga/sample_adt_mllp.hl7
printf "\x1c\x0d" >> /home/ga/sample_adt_mllp.hl7

# Replace the user-facing file with the MLLP version so 'cat file | nc' works out of the box
mv /home/ga/sample_adt_mllp.hl7 /home/ga/sample_adt.hl7
chown ga:ga /home/ga/sample_adt.hl7

# 2. Setup Webhook Server
# We run a python server in a container attached to the same network as NextGen Connect
echo "Setting up Webhook Server..."
mkdir -p /tmp/webhook_data
chmod 777 /tmp/webhook_data
rm -f /tmp/webhook_data/payloads.log

# Create the python server script
cat > /tmp/webhook_data/server.py << 'PYEOF'
import http.server
import json
import time
import sys

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        
        try:
            # decode and log
            payload = post_data.decode('utf-8')
            print(f"Received POST request to {self.path}")
            print(f"Payload: {payload}")
            
            # Log to file shared with host
            with open('/data/payloads.log', 'a') as f:
                log_entry = {
                    'timestamp': time.time(),
                    'path': self.path,
                    'headers': str(self.headers),
                    'body': payload
                }
                f.write(json.dumps(log_entry) + '\n')
                
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "received"}')
            
        except Exception as e:
            print(f"Error processing request: {e}")
            self.send_response(500)
            self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Webhook server running")

if __name__ == '__main__':
    print("Starting webhook server on port 8888")
    server_address = ('', 8888)
    httpd = http.server.HTTPServer(server_address, WebhookHandler)
    httpd.serve_forever()
PYEOF

# Pull python image if needed (should be cached or quick)
docker pull python:3.9-slim-buster >/dev/null 2>&1 || true

# Kill existing if any
docker rm -f webhook-server 2>/dev/null || true

# Run the webhook container
# Attached to 'nextgen-network' so it's reachable by 'webhook-server' hostname
docker run -d \
    --name webhook-server \
    --network nextgen-network \
    -v /tmp/webhook_data:/data \
    python:3.9-slim-buster \
    python3 -u /data/server.py

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Start Firefox and navigate to landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="