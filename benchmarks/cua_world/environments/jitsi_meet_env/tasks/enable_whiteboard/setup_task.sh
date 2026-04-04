#!/bin/bash
set -e

echo "=== Setting up enable_whiteboard task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming: container restart must happen AFTER this)
date +%s > /tmp/task_start_time.txt

# 1. Ensure Jitsi is running initially
cd /home/ga/jitsi
if ! docker compose ps --services --filter "status=running" | grep -q "web"; then
    echo "Starting Jitsi containers..."
    docker compose up -d
    wait_for_http "http://localhost:8080" 120
fi

# 2. Ensure Whiteboard is DISABLED initially
ENV_FILE="/home/ga/jitsi/.env"
if grep -q "WHITEBOARD_ENABLED" "$ENV_FILE"; then
    echo "Removing existing whiteboard config..."
    # Remove lines containing WHITEBOARD_ENABLED or WHITEBOARD_COLLAB_SERVER_PUBLIC_URL
    sed -i '/WHITEBOARD_ENABLED/d' "$ENV_FILE"
    sed -i '/WHITEBOARD_COLLAB_SERVER_PUBLIC_URL/d' "$ENV_FILE"
    
    # Restart to ensure clean state
    docker compose restart web
    wait_for_http "http://localhost:8080" 120
fi

# 3. Setup Browser
echo "Starting Firefox..."
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# 4. Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Enable whiteboard in .env, restart web container, and use whiteboard in meeting."