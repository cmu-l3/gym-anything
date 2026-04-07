#!/bin/bash
set -e
echo "=== Setting up configure_daemon_bridge_subnet task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon..."
wait_for_docker_daemon 60

# Record initial network state
echo "Recording initial bridge configuration..."
INITIAL_SUBNET=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "error")
INITIAL_GATEWAY=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo "error")

echo "$INITIAL_SUBNET" > /tmp/initial_subnet.txt
echo "$INITIAL_GATEWAY" > /tmp/initial_gateway.txt

echo "Initial state: Subnet=$INITIAL_SUBNET, Gateway=$INITIAL_GATEWAY"

# Focus Docker Desktop window
focus_docker_desktop

# Maximize window for visibility
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "docker" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Current Subnet: $INITIAL_SUBNET"
echo "Target Subnet:  192.168.200.0/24"