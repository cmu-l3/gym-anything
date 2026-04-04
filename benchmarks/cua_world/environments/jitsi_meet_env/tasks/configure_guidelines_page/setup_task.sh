#!/bin/bash
set -e
echo "=== Setting up configure_guidelines_page task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running and reachable
echo "Waiting for Jitsi Meet..."
if ! wait_for_http "http://localhost:8080" 120; then
    echo "ERROR: Jitsi Meet did not start in time."
    exit 1
fi

# Determine docker compose command
DOCKER_COMPOSE="docker compose"
if ! docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
fi

# Verify containers are running
cd /home/ga/jitsi
RUNNING_COUNT=$($DOCKER_COMPOSE ps --format '{{.Service}}' 2>/dev/null | wc -l)
if [ "$RUNNING_COUNT" -lt 4 ]; then
    echo "Restarting Jitsi containers..."
    $DOCKER_COMPOSE up -d
    sleep 15
    wait_for_http "http://localhost:8080" 120
fi

# Identify the web container
WEB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i web | head -1)
if [ -z "$WEB_CONTAINER" ]; then
    echo "ERROR: Web container not found!"
    exit 1
fi
echo "$WEB_CONTAINER" > /tmp/web_container_name.txt

# Record initial state: confirm /guidelines does NOT exist yet
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/guidelines" 2>/dev/null || echo "000")
echo "$HTTP_CODE" > /tmp/initial_guidelines_status.txt
echo "Initial /guidelines HTTP status: $HTTP_CODE"

# Clean up any artifacts from previous runs
rm -f /home/ga/guidelines.html 2>/dev/null || true
docker exec "$WEB_CONTAINER" rm -f /usr/share/jitsi-meet/guidelines.html 2>/dev/null || true

# Start Firefox at Jitsi welcome page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="