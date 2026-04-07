#!/bin/bash
# Setup script for run_container task (pre_task hook)
# Records initial state and ensures clean environment

echo "=== Setting up run_container task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon..."
for i in {1..30}; do
    if docker_daemon_ready; then
        echo "Docker daemon ready"
        break
    fi
    sleep 2
done

# Remove any existing container with the target name
echo "Cleaning up existing container..."
docker stop my-nginx-server 2>/dev/null || true
docker rm my-nginx-server 2>/dev/null || true

# Ensure the nginx:alpine image is available
echo "Ensuring nginx:alpine image is available..."
if ! image_exists "nginx:alpine"; then
    docker pull nginx:alpine
fi

# Record initial container count
INITIAL_CONTAINER_COUNT=$(get_container_count "all")
INITIAL_RUNNING_COUNT=$(get_container_count "running")
echo "$INITIAL_CONTAINER_COUNT" > /tmp/initial_container_count
echo "$INITIAL_RUNNING_COUNT" > /tmp/initial_running_count

# Record initial container list
docker ps -a --format '{{.Names}}' > /tmp/initial_containers.txt 2>/dev/null || true

# Focus Docker Desktop
focus_docker_desktop

# Maximize window
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo ""
echo "=== Task setup complete ==="
echo "Initial container count: $INITIAL_CONTAINER_COUNT (running: $INITIAL_RUNNING_COUNT)"
echo ""
echo "Target: Create and run container named 'my-nginx-server' from nginx:alpine"
echo "        with port mapping 8888:80"
echo ""
