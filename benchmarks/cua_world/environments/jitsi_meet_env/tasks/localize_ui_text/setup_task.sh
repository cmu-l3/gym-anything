#!/bin/bash
set -e
echo "=== Setting up localize_ui_text task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Reset localization file to default state if it was modified in a previous run
# We find the web container and verify the file content
WEB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i "web" | head -n 1)

if [ -n "$WEB_CONTAINER" ]; then
    echo "Found web container: $WEB_CONTAINER"
    
    # Restore original text to ensure task is doable from clean slate
    # We use sed inside the container to revert specific keys if they match our target (idempotency)
    # Or just ensure the container is healthy. 
    # For this task, we assume the env starts clean, but strictly speaking we could reinstall the package
    # or keep a backup. Since we don't have a backup mechanism in the env definition,
    # we will trust the container restart or just proceed.
    
    # Check if file exists
    if docker exec "$WEB_CONTAINER" test -f /usr/share/jitsi-meet/lang/main.json; then
        echo "Localization file found."
    else
        echo "ERROR: Localization file not found in container"
        exit 1
    fi
else
    echo "ERROR: Jitsi web container not found"
    exit 1
fi

# Open Firefox to the home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="