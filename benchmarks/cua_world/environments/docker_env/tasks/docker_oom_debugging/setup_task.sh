#!/bin/bash
# Setup script for docker_oom_debugging task
set -e

echo "=== Setting up Docker OOM Debugging Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
if ! docker info >/dev/null 2>&1; then
    echo "Waiting for Docker daemon..."
    for i in {1..60}; do
        if docker info >/dev/null 2>&1; then break; fi
        sleep 2
    done
fi

# Create project directory
PROJECT_DIR="/home/ga/projects/acme-worker-service"
mkdir -p "$PROJECT_DIR"

# Create Application Source
cat > "$PROJECT_DIR/app.py" << 'PYTHON_EOF'
import os
import time
import sys

def main():
    print("Starting Acme Worker Service v1.2...", flush=True)
    
    # Read configuration
    try:
        alloc_mb = int(os.environ.get('MAX_ALLOCATION_MB', '500'))
    except ValueError:
        print("Error: MAX_ALLOCATION_MB must be an integer", flush=True)
        sys.exit(1)
        
    print(f"Configuration: Target Memory Allocation = {alloc_mb} MB", flush=True)
    print("Initializing buffers...", flush=True)
    
    try:
        # Allocate memory (1MB chunks to avoid immediate fragmentation issues)
        buffer = []
        for i in range(alloc_mb):
            # 1 MB of 'x'
            buffer.append('x' * (1024 * 1024))
            if i % 50 == 0:
                print(f"  Allocated {i} MB...", flush=True)
                time.sleep(0.05) # Simulate initialization work
                
        print(f"SUCCESS: Fully allocated {alloc_mb} MB. Worker is ready.", flush=True)
        
        # Simulate work loop
        while True:
            time.sleep(1)
            
    except MemoryError:
        print("FATAL: MemoryError encountered during initialization!", flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
PYTHON_EOF

# Create Dockerfile
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE_EOF'
FROM python:3.11-slim
WORKDIR /app
COPY app.py .
CMD ["python", "-u", "app.py"]
DOCKERFILE_EOF

# Create docker-compose.yml with the BUG (500MB alloc > 300MB limit)
cat > "$PROJECT_DIR/docker-compose.yml" << 'COMPOSE_EOF'
services:
  worker:
    build: .
    container_name: acme-worker
    environment:
      # Controls how much RAM the application attempts to reserve for processing
      # Default: 500MB for high-performance mode
      - MAX_ALLOCATION_MB=500
    deploy:
      resources:
        limits:
          # Cluster quota - DO NOT CHANGE
          memory: 300M
    restart: always
COMPOSE_EOF

# Create README
cat > "$PROJECT_DIR/README.md" << 'README_EOF'
# Acme Worker Service

This service processes data batches in memory.

## Configuration

The service is configured via environment variables:

- `MAX_ALLOCATION_MB`: Controls the size of the in-memory processing buffer (in Megabytes). 
  Reduce this value if running in constrained environments.

## Deployment

Deploy with `docker compose up -d`.
The production cluster enforces a hard memory limit on this container.
README_EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Build and Start (This will start crash looping)
echo "Starting initial crash-looping state..."
cd "$PROJECT_DIR"
docker compose build
docker compose up -d

# Verify it's crashing (wait a few seconds for OOM to hit)
sleep 5
docker ps -a --filter "name=acme-worker"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Desktop directory
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Launch terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-worker-service && echo \"Acme Worker Service Diagnosis\"; echo \"Current Status: Crash Loop\"; echo; docker compose ps; echo; exec bash'" > /tmp/terminal.log 2>&1 &

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="