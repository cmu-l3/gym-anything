#!/bin/bash
set -e
echo "=== Setting up configure_low_bandwidth_profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for uptime and timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is reachable initially
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Define config path
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/config.js"

# Ensure config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Config file not found at $CONFIG_PATH. Attempting to locate..."
    # Fallback to copy from container if volume mapping failed (unlikely in this env)
    docker cp jitsi_meet_env-web-1:/config/config.js "$CONFIG_PATH" || true
fi

# Reset config to "High Bandwidth" state (Defaults)
# We use sed to ensure the target values are NOT set initially
echo "Resetting config.js to default state..."

# 1. Set startAudioOnly to false
sed -i 's/startAudioOnly: true/startAudioOnly: false/g' "$CONFIG_PATH"
# Ensure it exists if it was missing
if ! grep -q "startAudioOnly" "$CONFIG_PATH"; then
    # Insert it after the first brace
    sed -i "/^var config = {/a \    startAudioOnly: false," "$CONFIG_PATH"
fi

# 2. Reset constraints (comment them out or set to HD)
# We'll just comment out the constraints section if it exists to force agent to find/add it
# or set it to 720p if explicit
if grep -q "video: {" "$CONFIG_PATH"; then
    sed -i 's/ideal: 360/ideal: 720/g' "$CONFIG_PATH"
    sed -i 's/max: 360/max: 720/g' "$CONFIG_PATH"
    sed -i 's/min: 180/min: 240/g' "$CONFIG_PATH"
fi

# Ensure permissions are correct for ga user
chown ga:ga "$CONFIG_PATH"

# Restart Jitsi web to apply the "bad" state (so agent sees default behavior)
echo "Restarting web container to apply clean state..."
cd /home/ga/jitsi
docker compose restart web
sleep 5
wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 60

# Start Firefox at Jitsi home page
restart_firefox "http://localhost:8080" 8
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Config file located at: $CONFIG_PATH"