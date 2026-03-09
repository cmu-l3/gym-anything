#!/bin/bash
set -e
echo "=== Setting up enforce_display_name_policy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Jitsi is running and reachable
if ! wait_for_http "http://localhost:8080" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 2. Ensure configuration file exists and is in "false" state
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
CONFIG_FILE="$CONFIG_DIR/config.js"

# Create directory if it doesn't exist (it should from setup_jitsi.sh)
mkdir -p "$CONFIG_DIR"

# Check if config.js exists. If not, wait a bit for container to generate it, 
# or copy from the container if needed. 
# Usually Jitsi generates it on first run if missing.
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Waiting for config.js to be generated..."
    sleep 10
fi

# If still missing, we might need to extract it from the running container
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Extracting config.js from container..."
    # Determine container name (usually jitsi-web-1 or similar)
    CONTAINER_ID=$(docker ps | grep "jitsi/web" | awk '{print $1}' | head -1)
    if [ -n "$CONTAINER_ID" ]; then
        docker cp "$CONTAINER_ID":/config/config.js "$CONFIG_FILE"
        chown ga:ga "$CONFIG_FILE"
    else
        echo "ERROR: Could not find Jitsi Web container to extract config."
        # Create a dummy config if absolutely necessary (fallback)
        echo "var config = { hosts: { domain: 'localhost:8080' } };" > "$CONFIG_FILE"
        chown ga:ga "$CONFIG_FILE"
    fi
fi

# 3. Force the setting to FALSE initially (or comment it out)
# We use sed to ensure the task actually requires work.
if grep -q "requireDisplayName" "$CONFIG_FILE"; then
    # Change true to false
    sed -i 's/requireDisplayName: true/requireDisplayName: false/g' "$CONFIG_FILE"
    # Or just comment it out to be safe, but explicitly setting false is clearer for "undoing"
else
    # Append it at the end of the config object if missing (simplified approach)
    # Ideally, we insert it into the config object, but config.js is complex.
    # We'll assume the user might have to find it or add it. 
    # For setup, we verify it's NOT true.
    pass
fi

# Ensure permissions
chown ga:ga "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"

# 4. Clean up any previous evidence
rm -f /home/ga/evidence_disabled_button.png

# 5. Start Firefox at the home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Config file is at: $CONFIG_FILE"