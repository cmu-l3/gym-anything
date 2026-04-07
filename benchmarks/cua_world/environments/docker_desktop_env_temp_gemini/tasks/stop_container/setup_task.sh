#!/bin/bash
# Setup script for stop_container task (pre_task hook)
# Creates a running container that the agent must stop

echo "=== Setting up stop_container task ==="

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

# Ensure the nginx:alpine image is available
echo "Ensuring nginx:alpine image is available..."
if ! image_exists "nginx:alpine"; then
    docker pull nginx:alpine
fi

# Remove any existing container with the target name
echo "Cleaning up existing container..."
docker stop test-web-server 2>/dev/null || true
docker rm test-web-server 2>/dev/null || true

# Create and start the target container
echo "Creating and starting target container..."
docker run -d --name test-web-server -p 8080:80 nginx:alpine

# Verify container is running
sleep 2
if container_running "test-web-server"; then
    echo "Container 'test-web-server' is now running"
else
    echo "ERROR: Failed to start container"
fi

# Record initial state
echo "true" > /tmp/initial_container_running
INITIAL_RUNNING_COUNT=$(get_container_count "running")
echo "$INITIAL_RUNNING_COUNT" > /tmp/initial_running_count

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
echo "Running containers: $INITIAL_RUNNING_COUNT"
echo ""
echo "Target: Stop the container named 'test-web-server' using Docker Desktop"
echo ""
