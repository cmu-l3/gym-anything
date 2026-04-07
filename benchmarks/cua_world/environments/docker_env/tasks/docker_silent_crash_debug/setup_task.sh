#!/bin/bash
set -e
echo "=== Setting up Docker Silent Crash Debug Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
wait_for_docker

# Create project directory
PROJECT_DIR="/home/ga/projects/acme-sync"
mkdir -p "$PROJECT_DIR"

# Create the Python application that logs only to file
cat > "$PROJECT_DIR/app.py" << 'PYTHON_EOF'
import logging
import os
import sys
import time
import signal

# Ensure log directory exists
os.makedirs('/var/log/acme', exist_ok=True)

# Configure logging to FILE ONLY (The Problem)
logging.basicConfig(
    filename='/var/log/acme/sync.log',
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

def handle_sigterm(*args):
    logger.info("Received SIGTERM, shutting down...")
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)

def main():
    logger.info("Starting Acme Inventory Sync Service...")
    
    # Get configuration
    batch_size_env = os.environ.get('SYNC_BATCH_SIZE', '100')
    
    try:
        # The Crash: Trying to parse a string like "100 items" as int
        batch_size = int(batch_size_env)
        logger.info(f"Inventory sync initialized with batch size {batch_size}")
    except ValueError as e:
        logger.error(f"Configuration Error: Invalid batch size '{batch_size_env}'. Must be an integer.")
        logger.error(f"Traceback: {e}")
        # Crash immediately
        sys.exit(1)
        
    logger.info("Connection to inventory database established.")
    
    # Simulate work loop
    count = 0
    while True:
        count += 1
        if count % 10 == 0:
            logger.info(f"Synced batch {count}...")
        time.sleep(1)

if __name__ == "__main__":
    main()
PYTHON_EOF

# Create Dockerfile
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

# Create log directory
RUN mkdir -p /var/log/acme && chmod 777 /var/log/acme

COPY app.py .

CMD ["python", "-u", "app.py"]
DOCKERFILE_EOF

# Create broken docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" << 'YAML_EOF'
version: '3.8'

services:
  worker:
    build: .
    container_name: acme-sync-worker
    environment:
      # CONFIGURATION ERROR: The app expects an integer, not a string with units
      - SYNC_BATCH_SIZE="100 items"
    restart: always
YAML_EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Build and start the crashing container
echo "Building and starting crashing service..."
cd "$PROJECT_DIR"
# Use capture to avoid cluttering start logs, but ensure it runs
su - ga -c "docker compose up -d --build"

# Verify it's crashing (wait a few seconds for the crash loop to establish)
sleep 5
STATUS=$(docker inspect --format '{{.State.Restarting}}' acme-sync-worker 2>/dev/null || echo "false")
echo "Container restarting status: $STATUS"

# Verify logs are empty (setup check)
LOGS=$(docker logs acme-sync-worker 2>&1)
if [ -z "$LOGS" ]; then
    echo "Confirmed: docker logs are empty."
else
    echo "WARNING: docker logs are NOT empty (unexpected for this task setup): $LOGS"
fi

# Create Desktop directory for the report
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Record start time
date +%s > /tmp/task_start_timestamp

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-sync && echo \"Task: Diagnose and Fix Silent Crash\"; echo \"Service acme-sync-worker is restarting...\"; echo \"Check: docker ps\"; echo \"Check: docker logs acme-sync-worker\"; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="