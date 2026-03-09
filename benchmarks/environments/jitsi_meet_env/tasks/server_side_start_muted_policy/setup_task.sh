#!/bin/bash
set -euo pipefail

echo "=== Setting up server_side_start_muted_policy task ==="

source /workspace/scripts/task_utils.sh

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"

# Ensure config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

echo "Resetting configuration to default (unmuted)..."
# Force settings to false initially to ensure the agent has to change them
# We handle both commented and uncommented cases, and existing true/false values
# 1. Uncomment if commented
sed -i 's|//\s*startWithAudioMuted|startWithAudioMuted|g' "$CONFIG_FILE"
sed -i 's|//\s*startWithVideoMuted|startWithVideoMuted|g' "$CONFIG_FILE"

# 2. Set to false
sed -i 's|startWithAudioMuted:.*,|startWithAudioMuted: false,|g' "$CONFIG_FILE"
sed -i 's|startWithVideoMuted:.*,|startWithVideoMuted: false,|g' "$CONFIG_FILE"

echo "Configuration reset complete."

# Start Firefox at Jitsi home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Record start time and initial file timestamp
date +%s > /tmp/task_start_time.txt
stat -c %Y "$CONFIG_FILE" > /tmp/initial_config_mtime.txt

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "TASK: Edit $CONFIG_FILE to set startWithAudioMuted and startWithVideoMuted to true."