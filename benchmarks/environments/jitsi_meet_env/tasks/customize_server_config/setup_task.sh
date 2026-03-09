#!/bin/bash
set -e
echo "=== Setting up customize_server_config task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous task artifacts
echo "Cleaning up previous config and artifacts..."
rm -f /home/ga/.jitsi-meet-cfg/web/custom-config.js
rm -f /home/ga/jitsi_config_verification.png
rm -f /home/ga/custom_config_served.txt
rm -f /tmp/task_result.json

# 2. Ensure Jitsi is running in default state
echo "Ensuring Jitsi is running..."
cd /home/ga/jitsi

# Check if containers are running
if ! docker compose ps --services --filter "status=running" | grep -q "web"; then
    echo "Starting Jitsi containers..."
    docker compose up -d
    wait_for_http "http://localhost:8080" 300
fi

# Record initial container start time (to detect restart)
WEB_CONTAINER_ID=$(docker compose ps -q web)
docker inspect --format='{{.State.StartedAt}}' "$WEB_CONTAINER_ID" > /tmp/initial_web_start_time.txt

# 3. Open Firefox to default (English) page
echo "Opening Firefox..."
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="