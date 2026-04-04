#!/bin/bash
set -e
echo "=== Setting up enable_etherpad_notes task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running initially
wait_for_http "http://localhost:8080" 120

# Clean state: Remove any existing etherpad container
if docker ps -a --format '{{.Names}}' | grep -q "^etherpad$"; then
    echo "Removing stale etherpad container..."
    docker rm -f etherpad
fi

# Clean state: Remove any proof screenshots
rm -f /home/ga/etherpad_integration_proof.png

# Pre-pull the etherpad image to prevent timeouts during the task
# (This simulates the image being available in the local registry)
if ! docker image inspect etherpad/etherpad >/dev/null 2>&1; then
    echo "Pre-pulling etherpad/etherpad image..."
    docker pull etherpad/etherpad:latest || echo "WARNING: Failed to pull etherpad image"
fi

# Reset Jitsi config to default state (remove ETHERPAD_URL_BASE if present)
# We assume the user configures this via .env or compose override
if [ -f "/home/ga/jitsi/.env" ]; then
    sed -i '/ETHERPAD_URL_BASE/d' /home/ga/jitsi/.env
fi

# Restart Firefox on the home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Jitsi Meet is running at http://localhost:8080"
echo "Goal: Deploy Etherpad on port 9001 and integrate it with Jitsi."