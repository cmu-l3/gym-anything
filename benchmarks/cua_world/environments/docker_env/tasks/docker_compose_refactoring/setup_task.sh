#!/bin/bash
# Setup script for docker_compose_refactoring task
# Creates a redundant Docker Compose project that needs refactoring.

set -e
echo "=== Setting up Docker Compose Refactoring Task ==="

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

# 1. Clean up previous runs
echo "Cleaning up previous state..."
docker compose -f /home/ga/projects/media-pipeline/docker-compose.yml down --volumes --remove-orphans 2>/dev/null || true
rm -rf /home/ga/projects/media-pipeline

# 2. Create Project Directory
PROJECT_DIR="/home/ga/projects/media-pipeline"
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/media"

# 3. Create Dummy Application (so the stack is runnable)
cat > "$PROJECT_DIR/app/worker.py" << 'EOF'
import os
import time
import signal
import sys

service_name = os.environ.get("SERVICE_NAME", "unknown-worker")

def handle_sigterm(*args):
    print(f"[{service_name}] Received SIGTERM, shutting down...")
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)

print(f"[{service_name}] Worker started. Waiting for jobs...")
while True:
    time.sleep(10)
    print(f"[{service_name}] Heartbeat...")
EOF

cat > "$PROJECT_DIR/app/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY worker.py .
CMD ["python", "-u", "worker.py"]
EOF

# 4. Create the Repetitive docker-compose.yml
# Note: transcoder-h264 intentionally missing "restart: always"
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  transcoder-av1:
    build: ./app
    environment:
      - SERVICE_NAME=transcoder-av1
      - QUEUE=video-av1
    volumes:
      - ./media:/data/media
    networks:
      - pipeline-net
    restart: always
    stop_signal: SIGINT
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M

  transcoder-h264:
    build: ./app
    environment:
      - SERVICE_NAME=transcoder-h264
      - QUEUE=video-h264
    volumes:
      - ./media:/data/media
    networks:
      - pipeline-net
    # MISSING RESTART POLICY HERE (DRIFT)
    stop_signal: SIGINT
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M

  thumbnail-generator:
    build: ./app
    environment:
      - SERVICE_NAME=thumbnail-generator
      - QUEUE=images
    volumes:
      - ./media:/data/media
    networks:
      - pipeline-net
    restart: always
    stop_signal: SIGINT
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M

  audio-extractor:
    build: ./app
    environment:
      - SERVICE_NAME=audio-extractor
      - QUEUE=audio
    volumes:
      - ./media:/data/media
    networks:
      - pipeline-net
    restart: always
    stop_signal: SIGINT
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M

networks:
  pipeline-net:
    driver: bridge
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record initial line count
INITIAL_LINES=$(wc -l < "$PROJECT_DIR/docker-compose.yml")
echo "$INITIAL_LINES" > /tmp/initial_lines

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Create Desktop directory and open terminal
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/media-pipeline && echo \"Media Pipeline Refactoring Task\"; echo \"Current Line Count: $INITIAL_LINES\"; echo; echo \"Goal: Extract common config to docker-compose.base.yml and use extends.\"; echo \"      Also fix the missing restart policy in transcoder-h264.\"; echo; ls -la; exec bash'" > /tmp/refactor_terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project: $PROJECT_DIR"
echo "Initial lines: $INITIAL_LINES"