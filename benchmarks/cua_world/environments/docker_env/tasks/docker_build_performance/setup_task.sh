#!/bin/bash
# Setup script for docker_build_performance task

set -e
echo "=== Setting up Docker Build Performance Task ==="

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

# Set up project directory
PROJECT_DIR="/home/ga/projects/analytics-service"
mkdir -p "$PROJECT_DIR"

# Copy bloated project from workspace data
cp -r /workspace/data/task3_build/. "$PROJECT_DIR/"
chown -R ga:ga "$PROJECT_DIR"

# Build the ORIGINAL image (so the agent can measure it)
echo "Building original image acme-analytics:original..."
export DOCKER_BUILDKIT=1
docker build -t acme-analytics:original "$PROJECT_DIR/" --no-cache -q 2>&1 | tail -5 || {
    echo "Warning: original build failed or took too long"
}

# Also tag it as :optimized initially (agent must replace this)
docker tag acme-analytics:original acme-analytics:optimized 2>/dev/null || true

# Record initial image size
INITIAL_SIZE_MB=$(docker inspect acme-analytics:original --format '{{.Size}}' 2>/dev/null | \
    awk '{printf "%.0f", $1/1048576}' 2>/dev/null || echo "0")
echo "$INITIAL_SIZE_MB" > /tmp/initial_image_size_mb

# Record the original image ID — used by export to detect if agent replaced :optimized
docker inspect acme-analytics:optimized --format '{{.Id}}' 2>/dev/null > /tmp/initial_optimized_image_id || echo "" > /tmp/initial_optimized_image_id

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Open terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/analytics-service && echo \"Dockerfile Optimization Task\"; echo; echo \"Original image size:\"; docker images acme-analytics:original --format \"  {{.Repository}}:{{.Tag}} - {{.Size}}\"; echo; echo \"Goal: Rebuild as acme-analytics:optimized with size < 400MB\"; echo \"      and second build (cached) under 60 seconds\"; echo; cat Dockerfile; exec bash'" > /tmp/build_terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project: $PROJECT_DIR"
echo "Original image size: ${INITIAL_SIZE_MB}MB"
echo "Target: acme-analytics:optimized < 400MB"
