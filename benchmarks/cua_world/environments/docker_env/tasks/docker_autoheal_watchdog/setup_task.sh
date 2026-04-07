#!/bin/bash
set -e
echo "=== Setting up Docker Autoheal Watchdog Task ==="

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

# Clean up any previous runs
docker compose -f /home/ga/projects/payment-gateway/docker-compose.yml down 2>/dev/null || true
docker rm -f gateway watchdog 2>/dev/null || true

# Setup Project Directory
PROJECT_DIR="/home/ga/projects/payment-gateway"
mkdir -p "$PROJECT_DIR/gateway"

# 1. Create the Buggy Flask App
cat > "$PROJECT_DIR/gateway/main.py" << 'PYTHON_EOF'
from flask import Flask, jsonify, request
import time
import threading
import sys

app = Flask(__name__)

# Global flag to simulate broken state
is_broken = False
start_time = time.time()

@app.route('/')
def index():
    return jsonify({"service": "Payment Gateway", "status": "running", "uptime": time.time() - start_time})

@app.route('/health')
def health():
    global is_broken
    if is_broken:
        # Simulate a hang/deadlock - timeout or 500
        time.sleep(10) 
        return jsonify({"status": "unhealthy"}), 500
    return jsonify({"status": "healthy"}), 200

@app.route('/sabotage', methods=['POST'])
def sabotage():
    global is_broken
    is_broken = True
    print("CRITICAL: Service sabotaged! Deadlock simulated.", file=sys.stderr)
    return jsonify({"message": "Service sabotaged. Good luck."}), 200

if __name__ == '__main__':
    # Threaded=True is default, but we want to simulate the main thread "locking" logic effectively
    app.run(host='0.0.0.0', port=8000)
PYTHON_EOF

# 2. Create Dockerfile (No Healthcheck initially)
cat > "$PROJECT_DIR/gateway/Dockerfile" << 'DOCKERFILE_EOF'
FROM python:3.9-slim

WORKDIR /app

RUN pip install flask

COPY main.py .

# Standard startup
CMD ["python", "main.py"]
DOCKERFILE_EOF

# 3. Create docker-compose.yml (Naive configuration)
cat > "$PROJECT_DIR/docker-compose.yml" << 'COMPOSE_EOF'
version: '3.8'

services:
  gateway:
    build: ./gateway
    container_name: gateway
    ports:
      - "8000:8000"
    restart: always  # Only handles process crash, not hangs
COMPOSE_EOF

chown -R ga:ga "$PROJECT_DIR"

# Build and Start Initial State
echo "Starting initial stack..."
cd "$PROJECT_DIR"
docker compose up -d --build

# Record Task Start Time
date +%s > /tmp/task_start_timestamp

# Wait for service to be ready
echo "Waiting for gateway to start..."
wait_for_port localhost 8000 30 || echo "Warning: Gateway slow to start"

# Open Terminal for Agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/payment-gateway && echo \"=== Docker Autoheal Task ===\"; echo \"Current Status: Gateway running (restart: always)\"; echo \"Problem: Process stays running when frozen.\"; echo \"Task: Implement a watchdog sidecar to restart gateway when /health fails.\"; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="