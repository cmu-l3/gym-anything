#!/bin/bash
set -e
echo "=== Setting up Hybrid Network Debug Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for screenshot
take_screenshot() {
    DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
}

# Wait for Docker
wait_for_docker

# 1. Prepare Project Directory
PROJECT_DIR="/home/ga/projects/hybrid-migration"
mkdir -p "$PROJECT_DIR/backend"
mkdir -p "$PROJECT_DIR/frontend"

# 2. Create Legacy Inventory Service (Host App)
# This mimics a legacy app running on "bare metal" (the container's OS in this context)
cat > "$PROJECT_DIR/legacy_inventory.py" << 'EOF'
import http.server
import socketserver
import json

PORT = 9090

class InventoryHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        # Return dummy inventory data
        data = {
            "id": 101,
            "item": "Retro Lamp",
            "stock": 42,
            "origin": "Legacy Host System"
        }
        self.wfile.write(json.dumps(data).encode())
    
    def log_message(self, format, *args):
        return # Silence logs

print(f"Legacy Inventory Service running on port {PORT}...")
with socketserver.TCPServer(("0.0.0.0", PORT), InventoryHandler) as httpd:
    httpd.serve_forever()
EOF

# 3. Create Backend (Python Flask)
cat > "$PROJECT_DIR/backend/app.py" << 'EOF'
import os
import sys
import json
import urllib.request
from flask import Flask, jsonify

app = Flask(__name__)

# BUG 1: Default points to localhost (which is the container, not the host)
INVENTORY_URL = os.environ.get('INVENTORY_URL', 'http://localhost:9090')

@app.route('/api/product')
def get_product():
    try:
        print(f"Connecting to Legacy Service at {INVENTORY_URL}...", file=sys.stderr)
        with urllib.request.urlopen(INVENTORY_URL, timeout=2) as response:
            data = json.loads(response.read().decode())
            return jsonify({
                "service": "Shop Backend",
                "inventory": data
            })
    except Exception as e:
        print(f"Connection failed: {e}", file=sys.stderr)
        return jsonify({"error": f"Could not reach legacy inventory: {str(e)}"}), 502

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "$PROJECT_DIR/backend/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install flask
COPY app.py .
CMD ["python", "app.py"]
EOF

# 4. Create Frontend (Node.js)
cat > "$PROJECT_DIR/frontend/server.js" << 'EOF'
const http = require('http');

// BUG 2: Default points to wrong service name 'shop-api'
const API_URL = process.env.API_URL || 'http://shop-api:5000/api/product';

const server = http.createServer((req, res) => {
    console.log(`Frontend fetching from ${API_URL}...`);
    
    const request = http.get(API_URL, (apiRes) => {
        let data = '';
        apiRes.on('data', (chunk) => data += chunk);
        apiRes.on('end', () => {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                frontend: "Shop Frontend",
                backend_response: JSON.parse(data)
            }));
        });
    });

    request.on('error', (err) => {
        console.error(`Error connecting to backend: ${err.message}`);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: "Frontend failed to call Backend", details: err.message }));
    });
});

// App listens on 3000
const PORT = 3000;
server.listen(PORT, () => {
    console.log(`Frontend running on port ${PORT}`);
});
EOF

cat > "$PROJECT_DIR/frontend/package.json" << 'EOF'
{
  "name": "shop-frontend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" }
}
EOF

cat > "$PROJECT_DIR/frontend/Dockerfile" << 'EOF'
FROM node:20-slim
WORKDIR /app
COPY package.json server.js ./
CMD ["node", "server.js"]
EOF

# 5. Create Broken Docker Compose File
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  shop-backend:
    build: ./backend
    environment:
      # BUG 1: 'localhost' refers to this container, not the host machine
      - INVENTORY_URL=http://localhost:9090
    # MISSING: extra_hosts for host.docker.internal

  shop-frontend:
    build: ./frontend
    environment:
      # BUG 2: Service name is 'shop-backend', not 'shop-api'
      - API_URL=http://shop-api:5000/api/product
    ports:
      # BUG 3: Container listens on 3000, but mapped to 8080:8080
      - "8080:8080"
    depends_on:
      - shop-backend
EOF

# 6. Start the Legacy Inventory Service on the Host
# Kill any existing instance
pkill -f "legacy_inventory.py" || true
# Start in background
nohup python3 "$PROJECT_DIR/legacy_inventory.py" > /tmp/legacy_inventory.log 2>&1 &
echo "Legacy Inventory Service started (PID $!)."

# 7. Pre-build and start the broken stack
# We want the agent to see running (but failing) containers if possible, or exit loops
chown -R ga:ga "$PROJECT_DIR"

echo "Building and starting initial broken stack..."
cd "$PROJECT_DIR"
# We run as ga to ensure permissions are right for the agent
su - ga -c "docker compose build"
su - ga -c "docker compose up -d"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Launch a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/hybrid-migration && echo \"Hybrid Network Debug Task\"; echo \"Legacy Inventory Service is running on Host Port 9090\"; echo; docker compose ps; echo; echo \"Check connectivity: curl -v http://localhost:8080\"; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="