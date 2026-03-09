#!/bin/bash
# Setup script for multi_network_isolation task

echo "=== Setting up multi_network_isolation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

# Wait for Docker daemon
echo "Waiting for Docker daemon..."
wait_for_docker_daemon 60

# Clean up any existing resources to ensure a fresh start
echo "Cleaning up stale resources..."
docker rm -f web-proxy app-server data-store 2>/dev/null || true
docker network rm frontend backend 2>/dev/null || true

# Pre-pull images to save time/bandwidth during the task
echo "Pre-pulling required images..."
docker pull nginx:alpine 2>/dev/null || true
docker pull httpd:alpine 2>/dev/null || true
docker pull redis:alpine 2>/dev/null || true

# Record initial state
echo "Recording initial state..."
docker ps -a --format '{{.Names}}' > /tmp/initial_containers.txt
docker network ls --format '{{.Name}}' > /tmp/initial_networks.txt

# Focus Docker Desktop window
focus_docker_desktop

# Maximize window
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Clean state established."
echo "Images pre-pulled: nginx:alpine, httpd:alpine, redis:alpine"