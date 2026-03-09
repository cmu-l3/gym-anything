#!/bin/bash
set -e
echo "=== Setting up Configure High FPS Screenshare task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Ensure config file exists (it is volume mounted)
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Waiting for config file generation..."
    for i in {1..30}; do
        if [ -f "$CONFIG_FILE" ]; then
            break
        fi
        sleep 2
    done
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Backup the original config (hidden from agent, for restoration if needed)
cp "$CONFIG_FILE" "/tmp/config.js.bak"

# Ensure we start with default low FPS values to ensure the task is meaningful
# We use sed to force specific bad values if they aren't there, or just rely on defaults.
# Jitsi default is usually 5. Let's ensure it's NOT 30 already.
sed -i 's/desktopSharingFrameRate:.*,/desktopSharingFrameRate: { min: 5, max: 5 },/' "$CONFIG_FILE"
sed -i 's/enableLayerSuspension:.*/enableLayerSuspension: false,/' "$CONFIG_FILE"

# Restart containers to apply this "bad" state if we modified it
cd /home/ga/jitsi
docker compose restart web
wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 60

# Open Firefox to the home page to provide a visual starting point
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Create a clean state for the report file
rm -f /home/ga/fps_config_report.txt

echo "=== Task setup complete ==="
echo "Config file located at: $CONFIG_FILE"
echo "Current state: Low FPS (5) and Layer Suspension Disabled"