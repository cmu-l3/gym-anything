#!/bin/bash
set -e
echo "=== Setting up Configure High Capacity Monitoring task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
echo "Waiting for Jitsi Meet to be ready..."
if ! wait_for_http "http://localhost:8080" 120; then
    echo "ERROR: Jitsi Meet did not start in time."
    exit 1
fi

# Ensure Firefox is closed initially to encourage agent to check config first or start fresh
stop_firefox

# We want to ensure the config file exists and is in a default state before the agent starts.
# The Jitsi web container generates config.js in the config volume if it doesn't exist.
# The volume path in this env is /home/ga/.jitsi-meet-cfg/web
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
    # Fallback: copy from container if possible, or fail
    exit 1
fi

# Reset to known default state (just in case previous runs messed it up)
# We use sed to ensure the target values are NOT currently set to the goal values
sed -i 's/channelLastN: -1/channelLastN: -2/' "$CONFIG_FILE"
sed -i 's/enableLayerSuspension: false/enableLayerSuspension: true/' "$CONFIG_FILE"
sed -i 's/disableAudioLevels: true/disableAudioLevels: false/' "$CONFIG_FILE"

# Restart web container to apply reset (silently)
cd /home/ga/jitsi
docker compose restart web > /dev/null 2>&1
wait_for_http "http://localhost:8080" 60

# Open Firefox to the homepage
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="