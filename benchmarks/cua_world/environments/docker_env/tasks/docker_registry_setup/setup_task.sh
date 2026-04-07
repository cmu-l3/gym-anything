#!/bin/bash
set -e
echo "=== Setting up Docker Registry Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for Docker readiness
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

wait_for_docker

# 1. Clean up previous runs
echo "Cleaning up previous state..."
docker rm -f acme-registry 2>/dev/null || true
docker volume rm registry-data 2>/dev/null || true
# Clean up any images from previous runs to ensure clean slate
docker images --format '{{.Repository}}:{{.Tag}}' | grep "registry.acme.local" | xargs -r docker rmi -f 2>/dev/null || true

# 2. Setup Project Directory
PROJECT_DIR="/home/ga/projects/registry-setup"
mkdir -p "$PROJECT_DIR"
chown -R ga:ga "/home/ga/projects"

# 3. Setup DNS alias
# Add registry.acme.local to /etc/hosts if not present
if ! grep -q "registry.acme.local" /etc/hosts; then
    echo "127.0.0.1 registry.acme.local" | sudo tee -a /etc/hosts > /dev/null
fi

# 4. Prepare "Source" Images
# We simulate app images by tagging standard base images. 
# This ensures they exist locally for the agent to use.
echo "Preparing source application images..."

# Ensure we have base images (loaded by env setup, but pull if missing)
docker pull python:3.11-slim 2>/dev/null || true
docker pull node:20-slim 2>/dev/null || true
docker pull nginx:1.24-alpine 2>/dev/null || true
docker pull registry:2 2>/dev/null || true

# Create the "acme" source images
docker tag python:3.11-slim acme-api:latest
docker tag node:20-slim acme-frontend:latest
docker tag nginx:1.24-alpine acme-proxy:latest

echo "Source images created:"
docker images | grep "acme-"

# 5. Record Start State
date +%s > /tmp/task_start_time.txt
echo "Task initialized at $(cat /tmp/task_start_time.txt)"

# 6. Launch Terminal for Agent
# We give them a clear starting point
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/registry-setup && echo \"=== Docker Registry Setup Task ===\"; echo \"Source images available:\"; docker images | grep acme-; echo; echo \"Ready to configure registry.acme.local\"; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 5

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="