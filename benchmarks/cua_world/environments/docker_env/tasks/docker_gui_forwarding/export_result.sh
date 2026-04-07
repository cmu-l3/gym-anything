#!/bin/bash
echo "=== Exporting Docker GUI Forwarding Results ==="

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Identify the container
# We look for a running container that might be the user's solution.
# Strategy: Find container running 'xeyes' or started from project dir
CONTAINER_ID=""

# Check if docker compose was used
cd /home/ga/projects/gui-sim
COMPOSE_CONTAINER=$(docker compose ps -q 2>/dev/null | head -n 1)

if [ -n "$COMPOSE_CONTAINER" ]; then
    CONTAINER_ID="$COMPOSE_CONTAINER"
    echo "Found container via docker compose: $CONTAINER_ID"
else
    # Fallback: search for any container running xeyes
    CONTAINER_ID=$(docker ps -q | xargs -r docker inspect --format '{{.Id}} {{.Config.Cmd}} {{.Config.Image}}' | grep -i "xeyes" | awk '{print $1}' | head -n 1)
    echo "Found container via process search: $CONTAINER_ID"
fi

# 3. Check Container Status
IS_RUNNING=0
PROCESS_INSIDE=0
HAS_DISPLAY_ENV=0
HAS_SOCKET_MOUNT=0

if [ -n "$CONTAINER_ID" ]; then
    # Check if running
    STATE=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_ID" 2>/dev/null)
    if [ "$STATE" == "true" ]; then
        IS_RUNNING=1
    fi

    # Check if xeyes process is running INSIDE
    if docker exec "$CONTAINER_ID" pidof xeyes > /dev/null 2>&1; then
        PROCESS_INSIDE=1
    fi

    # Check Environment Variables for DISPLAY
    if docker inspect -f '{{json .Config.Env}}' "$CONTAINER_ID" | grep -q "DISPLAY="; then
        HAS_DISPLAY_ENV=1
    fi

    # Check Mounts for /tmp/.X11-unix
    if docker inspect -f '{{json .Mounts}}' "$CONTAINER_ID" | grep -q "/tmp/.X11-unix"; then
        HAS_SOCKET_MOUNT=1
    fi
fi

# 4. Check Window Visibility on Host
WINDOW_VISIBLE=0
# wmctrl -l lists managed windows. We look for 'xeyes'. 
# Note: xeyes title is usually "xeyes"
if DISPLAY=:1 wmctrl -l | grep -i "xeyes" > /dev/null; then
    WINDOW_VISIBLE=1
fi

# 5. Check if Dockerfile exists
DOCKERFILE_EXISTS=0
if [ -f "/home/ga/projects/gui-sim/Dockerfile" ]; then
    DOCKERFILE_EXISTS=1
fi

# 6. Check if docker-compose.yml exists
COMPOSE_FILE_EXISTS=0
if [ -f "/home/ga/projects/gui-sim/docker-compose.yml" ]; then
    COMPOSE_FILE_EXISTS=1
fi

# Create JSON Result
cat > /tmp/task_result.json <<EOF
{
    "container_found": $([ -n "$CONTAINER_ID" ] && echo "true" || echo "false"),
    "container_running": $IS_RUNNING,
    "process_running_inside": $PROCESS_INSIDE,
    "window_visible_on_host": $WINDOW_VISIBLE,
    "config_has_display": $HAS_DISPLAY_ENV,
    "config_has_socket": $HAS_SOCKET_MOUNT,
    "dockerfile_exists": $DOCKERFILE_EXISTS,
    "compose_file_exists": $COMPOSE_FILE_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date +%s)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="