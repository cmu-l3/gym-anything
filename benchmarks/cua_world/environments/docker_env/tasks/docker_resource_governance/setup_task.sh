#!/bin/bash
set -e
echo "=== Setting up Docker Resource Governance Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for wait_for_docker
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

# Cleanup previous state
echo "Cleaning up existing containers..."
docker rm -f acme-api acme-worker acme-cache 2>/dev/null || true

# Setup directories
PROJECT_DIR="/home/ga/projects/resource-governance"
mkdir -p "$PROJECT_DIR/api" "$PROJECT_DIR/worker"
mkdir -p /home/ga/Desktop

# Create dummy API application
cat > "$PROJECT_DIR/api/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
# Simple HTTP server that simulates an API
CMD ["python3", "-m", "http.server", "5000"]
EOF

# Create dummy Worker application
cat > "$PROJECT_DIR/worker/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
# Loop to simulate a worker process
CMD ["sh", "-c", "while true; do echo 'Working...'; sleep 5; done"]
EOF

chown -R ga:ga "$PROJECT_DIR"
chown ga:ga /home/ga/Desktop

# Build images
echo "Building task images..."
docker build -t acme-api:latest "$PROJECT_DIR/api"
docker build -t acme-worker:latest "$PROJECT_DIR/worker"

# Start containers with NO limits
echo "Starting containers..."
# redis:7-alpine is pre-loaded in the environment
docker run -d --name acme-cache redis:7-alpine
docker run -d --name acme-api -p 5000:5000 acme-api:latest
docker run -d --name acme-worker acme-worker:latest

# Verify they are running
sleep 2
if [ $(docker ps -q | wc -l) -lt 3 ]; then
    echo "ERROR: Failed to start all 3 containers"
    docker ps -a
    exit 1
fi

# Record initial state (ensure no limits set)
# We record 0 to prove they started with 0
echo "0" > /tmp/initial_memory_limit
echo "0" > /tmp/initial_cpu_limit

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open terminal for user
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"Resource Governance Task Started\"; echo \"--------------------------------\"; echo \"Current Status:\"; docker stats --no-stream; echo; echo \"Task: Apply resource limits to acme-api, acme-worker, and acme-cache.\"; echo \"      See task description for details.\"; exec bash'" > /tmp/terminal_launch.log 2>&1 &

# Initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="