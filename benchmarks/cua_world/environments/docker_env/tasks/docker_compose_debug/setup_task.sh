#!/bin/bash
# Setup script for docker_compose_debug task

set -e
echo "=== Setting up Docker Compose Debug Task ==="

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

# Stop and clean up any running compose stacks from previous tasks
echo "Cleaning up any previous compose stacks..."
cd /home/ga/projects/ecommerce-app 2>/dev/null && docker compose down --volumes --remove-orphans 2>/dev/null || true
docker rm -f acme-db acme-cache acme-api acme-nginx acme-worker 2>/dev/null || true

# Set up project directory
echo "Setting up project directory..."
PROJECT_DIR="/home/ga/projects/ecommerce-app"
mkdir -p "$PROJECT_DIR"

# Copy the broken compose app from workspace data
cp -r /workspace/data/task2_compose/. "$PROJECT_DIR/"
chown -R ga:ga "$PROJECT_DIR"

# Record baseline (all services should be down)
INITIAL_RUNNING=$(docker ps --format '{{.Names}}' | grep -c "acme-" 2>/dev/null)
[ -z "$INITIAL_RUNNING" ] && INITIAL_RUNNING=0
echo "$INITIAL_RUNNING" > /tmp/initial_compose_running

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Open terminal with context
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/ecommerce-app && echo \"E-Commerce App Debug Task\"; echo \"Project: ~/projects/ecommerce-app/\"; echo; echo \"Try: docker compose up\"; echo \"Then diagnose failures with: docker logs <container>\"; echo; ls -la; exec bash'" > /tmp/compose_terminal.log 2>&1 &
sleep 3

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project: $PROJECT_DIR"
echo "Task: Find and fix 5 configuration bugs so all services run"
