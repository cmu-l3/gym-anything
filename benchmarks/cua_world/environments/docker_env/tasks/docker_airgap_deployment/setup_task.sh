#!/bin/bash
set -e
echo "=== Setting up Air-Gapped Deployment Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper definitions if utils not present
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

wait_for_docker

# 1. Create the application source code
PROJECT_DIR="/home/ga/projects/inventory-tracker"
mkdir -p "$PROJECT_DIR"

# app.py
cat > "$PROJECT_DIR/app.py" << 'EOF'
from flask import Flask, jsonify
import os
import socket

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        "service": "Inventory Tracker",
        "status": "online",
        "host": socket.gethostname(),
        "environment": "secure-prod"
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# requirements.txt
echo "flask==3.0.0" > "$PROJECT_DIR/requirements.txt"

# Dockerfile
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

chown -R ga:ga "$PROJECT_DIR"

# 2. Set up the "Air-Gapped" Remote Host (Docker-in-Docker)
# We use a dind container attached to an internal network to simulate isolation
echo "Setting up isolated remote environment..."

# Clean up previous runs
docker rm -f prod-secure 2>/dev/null || true
docker network rm secure-net 2>/dev/null || true

# Create internal network (no internet access)
docker network create --internal --driver bridge secure-net

# Start dind container
# -p 2375:2375 exposes the daemon to the agent
# -p 8080:8080 exposes the deployed app to the agent
# --privileged is required for dind
# DOCKER_TLS_CERTDIR="" disables TLS for simplicity in this task
docker run -d --privileged --name prod-secure \
    --network secure-net \
    -p 2375:2375 \
    -p 8080:8080 \
    -e DOCKER_TLS_CERTDIR="" \
    docker:dind

# Wait for remote daemon to be ready
echo "Waiting for remote daemon..."
for i in {1..30}; do
    if docker -H tcp://localhost:2375 info >/dev/null 2>&1; then
        echo "Remote daemon ready."
        break
    fi
    sleep 2
done

# Verify isolation (attempt to pull alpine on remote should fail)
echo "Verifying network isolation..."
if docker -H tcp://localhost:2375 pull alpine:latest >/dev/null 2>&1; then
    echo "WARNING: Remote host has internet access! Isolation failed."
else
    echo "Confirmed: Remote host cannot pull images (Network Unreachable)."
fi

# Record start state
date +%s > /tmp/task_start_time.txt

# Create a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/inventory-tracker && echo \"== Secure Deployment Task ==\"; echo \"Remote Daemon: tcp://localhost:2375\"; echo \"Project Dir: ~/projects/inventory-tracker\"; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &

sleep 3
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start.png
fi

echo "=== Setup Complete ==="