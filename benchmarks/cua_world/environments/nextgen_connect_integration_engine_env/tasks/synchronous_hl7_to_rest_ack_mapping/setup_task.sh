#!/bin/bash
echo "=== Setting up Synchronous HL7-to-REST Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create and start the Mock MPI REST API Server
cat > /home/ga/mock_mpi_server.py << 'EOF'
import http.server
import socketserver
import json
import uuid
import sys
from datetime import datetime

PORT = 9000
LOG_FILE = "/tmp/mock_mpi_server.log"

class MPIRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/patients':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                data = json.loads(post_data.decode('utf-8'))
                
                # Generate a deterministic but unique-looking UUID based on MRN if possible, or random
                generated_uuid = str(uuid.uuid4())
                
                response_data = {
                    "status": "success",
                    "mpi_uuid": generated_uuid,
                    "received_mrn": data.get("mrn", "unknown"),
                    "timestamp": datetime.now().isoformat()
                }
                
                # Log the transaction
                with open(LOG_FILE, "a") as f:
                    log_entry = {
                        "request": data,
                        "response": response_data,
                        "timestamp": datetime.now().isoformat()
                    }
                    f.write(json.dumps(log_entry) + "\n")
                
                # Send response
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(response_data).encode('utf-8'))
                
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

# Allow address reuse
socketserver.TCPServer.allow_reuse_address = True

print(f"Starting Mock MPI Server on port {PORT}")
with socketserver.TCPServer(("", PORT), MPIRequestHandler) as httpd:
    httpd.serve_forever()
EOF

# Kill any existing instance
pkill -f mock_mpi_server.py || true

# Start server in background
nohup python3 /home/ga/mock_mpi_server.py > /tmp/server_stdout.log 2>&1 &
echo $! > /tmp/mock_server.pid

# Wait for server to be up
echo "Waiting for Mock API..."
for i in {1..10}; do
    if curl -s http://localhost:9000/patients >/dev/null 2>&1 || curl -s -X POST http://localhost:9000/patients >/dev/null 2>&1; then
        echo "Mock API is up."
        break
    fi
    sleep 1
done

# 2. Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# 3. Open Terminal for user
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " Task: Synchronous HL7-to-REST Facade"
echo "======================================================="
echo " 1. Create Channel: MPI_Facade"
echo " 2. Source: TCP Listener (Port 6661)"
echo "    * RESPONSE: Destination 1"
echo " 3. Destination: HTTP Sender (http://localhost:9000/patients)"
echo "    * METHOD: POST"
echo "    * BODY: JSON {mrn, firstName, lastName}"
echo "    * RESPONSE TRANSFORMER: Parse JSON response -> HL7 ACK"
echo "      (MSA-3 must contain mpi_uuid from JSON)"
echo "======================================================="
echo " REST API is running at http://localhost:9000"
echo " NextGen Connect API: https://localhost:8443/api"
echo "======================================================="
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="