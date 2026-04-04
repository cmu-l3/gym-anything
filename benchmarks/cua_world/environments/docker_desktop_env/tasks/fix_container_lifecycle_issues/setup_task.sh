#!/bin/bash
# Setup script for fix_container_lifecycle_issues

set -e
echo "=== Setting up Lifecycle/Logging Task ==="

source /workspace/scripts/task_utils.sh

# Project location
PROJECT_DIR="/home/ga/Documents/docker-projects/order-processor"
mkdir -p "$PROJECT_DIR"

# 1. Create the problematic Python script
# It prints periodically but doesn't flush, and doesn't handle signals manually.
cat > "$PROJECT_DIR/processor.py" << 'EOF'
import time
import sys
import os
import datetime

print(f"[{datetime.datetime.now()}] Starting Order Processor (PID: {os.getpid()})...")

# Simulate initialization
time.sleep(1)
print(f"[{datetime.datetime.now()}] Initialization complete. Waiting for orders...")

# Main processing loop
count = 0
while True:
    count += 1
    # Standard print is buffered in Docker unless -u or PYTHONUNBUFFERED is set
    print(f"[{datetime.datetime.now()}] Processing order #{1000 + count} - Payment verified")
    
    # Simulate work
    time.sleep(2)
    
    # NOTE: This script has NO signal handling.
    # If run as PID 1, it will ignore SIGTERM and wait for SIGKILL (10s timeout).
EOF

# 2. Create Dockerfile (Missing buffering fix, missing init)
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM python:3.9-slim

WORKDIR /app
COPY processor.py .

# Running directly as python makes it PID 1
CMD ["python", "processor.py"]
EOF

# 3. Create docker-compose.yml (Missing init: true, missing environment vars)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  order-processor:
    build: .
    container_name: order-processor
    image: order-processor:v1
    # Missing: init: true (to fix PID 1 signal handling)
    # Missing: PYTHONUNBUFFERED=1 (to fix log delay)
    environment:
      - SERVICE_REGION=us-east-1
EOF

chown -R ga:ga "$PROJECT_DIR"

# 4. Ensure Docker Desktop is ready
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

wait_for_docker_daemon 60

# 5. Build and Start the broken container
# We start it so the user can immediately observe the issues:
# - Logs won't appear in 'docker logs' or desktop view
# - 'docker compose stop' will take 10s
echo "Building and starting initial state..."
cd "$PROJECT_DIR"
su - ga -c "docker compose build"
su - ga -c "docker compose up -d"

# 6. Setup desktop window
focus_docker_desktop
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Project created at: $PROJECT_DIR"
echo "Container 'order-processor' is running (with bugs)."