#!/bin/bash
echo "=== Setting up Containerize Host Integration Task ==="

source /workspace/scripts/task_utils.sh

# Project directory
PROJECT_DIR="/home/ga/Documents/docker-projects/migration-task"
mkdir -p "$PROJECT_DIR"

# 1. Create the Legacy Backend Service (running on HOST)
cat > /usr/local/bin/legacy_server.py << 'PYEOF'
import http.server
import socketserver
import json
import sys

PORT = 4567

class LegacyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {
            "status": "online",
            "system": "Mainframe_v2.4",
            "data": "Legacy Core Online"
        }
        self.wfile.write(json.dumps(response).encode())
    
    def log_message(self, format, *args):
        return # Squelch logs

if __name__ == "__main__":
    try:
        with socketserver.TCPServer(("0.0.0.0", PORT), LegacyHandler) as httpd:
            print(f"Legacy server running on port {PORT}")
            httpd.serve_forever()
    except OSError as e:
        print(f"Error starting server: {e}")
        sys.exit(1)
PYEOF

chmod +x /usr/local/bin/legacy_server.py

# Start the legacy server in background (as ga user)
pkill -f "legacy_server.py" 2>/dev/null || true
su - ga -c "python3 /usr/local/bin/legacy_server.py > /tmp/legacy_server.log 2>&1 &"

# Verify it started
sleep 2
if ! pgrep -f "legacy_server.py" > /dev/null; then
    echo "ERROR: Failed to start legacy server"
    exit 1
fi

# 2. Create the Frontend Application (Containerized)
mkdir -p "$PROJECT_DIR/app"

# App Code - Hardcoded hostname
cat > "$PROJECT_DIR/app/app.py" << 'PYEOF'
from flask import Flask, jsonify
import requests
import sys

app = Flask(__name__)

# CONSTRAINT: This hostname cannot be changed in source code
BACKEND_URL = "http://backend.legacy.internal:4567"

@app.route('/')
def index():
    try:
        # Attempt to contact legacy backend
        resp = requests.get(BACKEND_URL, timeout=2)
        data = resp.json()
        return jsonify({
            "status": "connected",
            "frontend_message": "Proxy successful",
            "backend_response": data.get("data", "Unknown")
        })
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e),
            "detail": "Could not resolve or connect to backend.legacy.internal"
        }), 502

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYEOF

# Requirements
cat > "$PROJECT_DIR/app/requirements.txt" << 'EOF'
flask
requests
EOF

# Dockerfile
cat > "$PROJECT_DIR/app/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "app.py"]
EOF

# Docker Compose - Missing the extra_hosts configuration
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  frontend:
    build: ./app
    container_name: frontend-app
    ports:
      - "8080:8080"
    # User needs to add extra_hosts here to map backend.legacy.internal to host-gateway
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 3. Record integrity data (Anti-gaming)
md5sum "$PROJECT_DIR/app/app.py" > /tmp/app_checksum.txt
date +%s > /tmp/task_start_time.txt

# 4. Open Docker Desktop and Terminal
if ! docker_desktop_running; then
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

# Open terminal at project location
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory='$PROJECT_DIR'" &

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Legacy server running on port 4567"
echo "Project files created at $PROJECT_DIR"