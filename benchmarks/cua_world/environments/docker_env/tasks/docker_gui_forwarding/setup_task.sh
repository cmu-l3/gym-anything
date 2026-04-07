#!/bin/bash
set -e
echo "=== Setting up Docker GUI Forwarding Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper to wait for docker if utils not loaded
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

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create project directory
PROJECT_DIR="/home/ga/projects/gui-sim"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# Clean up any existing state (stop previous containers, close windows)
echo "Cleaning up previous state..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" down 2>/dev/null || true
docker rm -f $(docker ps -a -q --filter "ancestor=xeyes-image") 2>/dev/null || true
pkill -f xeyes 2>/dev/null || true

# Ensure wmctrl and xhost are installed (host tools)
if ! command -v wmctrl &> /dev/null; then
    apt-get update && apt-get install -y wmctrl x11-xserver-utils
fi

# Reset xhost permissions to default (safe) state if possible, though strict reset might break env
# We just ensure the user can run xhost
if ! command -v xhost &> /dev/null; then
    apt-get install -y x11-xserver-utils
fi

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/gui-sim && echo \"GUI Forwarding Task\"; echo \"Goal: Run xeyes in Docker and display it on the host.\"; echo; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Project Directory: $PROJECT_DIR"