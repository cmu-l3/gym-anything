#!/bin/bash
# Setup script for docker_socket_proxy task

set -e
echo "=== Setting up Docker Socket Proxy Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

wait_for_docker

# Stop and remove any previous stack
if [ -d "/home/ga/projects/monitor-stack" ]; then
    cd /home/ga/projects/monitor-stack
    docker compose down --volumes --remove-orphans 2>/dev/null || true
fi

# Create project directory
PROJECT_DIR="/home/ga/projects/monitor-stack"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# 1. Create the Dashboard Application (Python script)
# It tries to connect via DOCKER_HOST (HTTP) or Unix Socket
cat > "$PROJECT_DIR/monitor.py" << 'EOF'
import os
import time
import socket
import http.client
import json
import sys
from urllib.parse import urlparse

def get_docker_client():
    docker_host = os.environ.get('DOCKER_HOST', 'unix:///var/run/docker.sock')
    
    if docker_host.startswith('tcp://'):
        # HTTP Connection
        parsed = urlparse(docker_host)
        host = parsed.hostname
        port = parsed.port or 2375
        print(f"Connecting to Docker via TCP: {host}:{port}")
        return http.client.HTTPConnection(host, port)
    elif docker_host.startswith('unix://'):
        # Unix Socket Connection
        socket_path = docker_host.replace('unix://', '')
        print(f"Connecting to Docker via Unix Socket: {socket_path}")
        
        class UnixHTTPConnection(http.client.HTTPConnection):
            def connect(self):
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(socket_path)
                
        return UnixHTTPConnection('localhost')
    else:
        print(f"Unknown DOCKER_HOST scheme: {docker_host}")
        sys.exit(1)

def monitor_loop():
    print("Starting Monitoring Dashboard...")
    while True:
        try:
            conn = get_docker_client()
            # Request container list (Safe/Allowed)
            conn.request("GET", "/containers/json")
            resp = conn.getresponse()
            data = resp.read().decode()
            
            if resp.status == 200:
                containers = json.loads(data)
                print(f"[SUCCESS] Monitoring {len(containers)} containers")
                for c in containers:
                    print(f"  - {c.get('Names', ['?'])[0]} ({c.get('Status')})")
            else:
                print(f"[ERROR] API returned {resp.status}: {data[:100]}")
            
            conn.close()
        except Exception as e:
            print(f"[FATAL] Connection failed: {e}")
        
        time.sleep(5)
        sys.stdout.flush()

if __name__ == "__main__":
    monitor_loop()
EOF

# 2. Create Dockerfile for Dashboard
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY monitor.py .
CMD ["python", "-u", "monitor.py"]
EOF

# 3. Create vulnerable docker-compose.yml
# Mounts the raw socket directly
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  dashboard:
    build: .
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    # No DOCKER_HOST set, python script defaults to unix:///var/run/docker.sock
EOF

chown -R ga:ga "$PROJECT_DIR"

# 4. Start the stack
echo "Starting vulnerable monitor stack..."
cd "$PROJECT_DIR"
export DOCKER_BUILDKIT=1
docker compose up -d --build

# Wait for it to be running
echo "Waiting for dashboard to stabilize..."
sleep 5
docker compose logs dashboard | tail -5

# Record initial state
date +%s > /tmp/task_start_timestamp
docker inspect $(docker compose ps -q dashboard) --format '{{json .Mounts}}' > /tmp/initial_mounts.json

# Open terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/monitor-stack && echo \"Monitor Stack Security Task\"; echo \"Current Status: Vulnerable (Raw Socket Mounted)\"; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project located at $PROJECT_DIR"