#!/bin/bash
set -euo pipefail

echo "=== Setting up Simplify Participant Interface task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Ensure configuration directory exists and we have permissions
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
mkdir -p "$CONFIG_DIR"
chown -R ga:ga "$CONFIG_DIR"

# Verify config.js exists. If it's missing (first run), the container usually creates it.
# If not, we might need to wait or trigger it.
if [ ! -f "$CONFIG_DIR/config.js" ]; then
    echo "Waiting for config.js to be generated..."
    # Accessing the web interface usually triggers generation if it's missing
    curl -s -k "https://localhost:8443/" > /dev/null || true
    sleep 5
fi

# Create a backup of the original config if it exists, to establish a baseline
if [ -f "$CONFIG_DIR/config.js" ]; then
    cp "$CONFIG_DIR/config.js" "$CONFIG_DIR/config.js.bak"
    echo "Backup created at $CONFIG_DIR/config.js.bak"
fi

# Start Firefox and join a meeting so the agent can see the initial complex toolbar
MEETING_URL="http://localhost:8080/YogaClass"
echo "Starting Firefox at $MEETING_URL..."
restart_firefox "$MEETING_URL" 10
maximize_firefox
focus_firefox

# Join the meeting automatically to reveal the toolbar
join_meeting 8

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Configuration files are located in: $CONFIG_DIR"