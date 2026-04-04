#!/bin/bash
# Setup script for pull_docker_image task (pre_task hook)
# Records initial state before the agent begins

echo "=== Setting up pull_docker_image task ==="

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

# Remove the target image if it exists (to ensure task requires pulling)
echo "Ensuring target image is not present..."
docker rmi python:3.11-slim 2>/dev/null || true
docker rmi python:3.11 2>/dev/null || true

# Record initial image count
INITIAL_IMAGE_COUNT=$(get_image_count)
echo "$INITIAL_IMAGE_COUNT" > /tmp/initial_image_count

# Record initial image list
docker images --format '{{.Repository}}:{{.Tag}}' > /tmp/initial_images.txt 2>/dev/null || true

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
echo "Initial image count: $INITIAL_IMAGE_COUNT"
echo ""
echo "Target: Pull python:3.11-slim using Docker Desktop"
echo ""
