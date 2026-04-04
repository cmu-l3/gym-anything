#!/bin/bash
set -e
echo "=== Setting up Configure Google Analytics task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Reset configuration to default state (remove any previous GA config)
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
CONFIG_FILE="$CONFIG_DIR/config.js"

if [ -f "$CONFIG_FILE" ]; then
    echo "Resetting config.js..."
    # Create backup
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    # Ensure googleAnalyticsTrackingId is NOT set or set to generic
    sed -i "s/googleAnalyticsTrackingId: .*,/googleAnalyticsTrackingId: 'UA-000000-0',/" "$CONFIG_FILE"
    
    # Ensure script is commented out or removed
    sed -i "s|'libs/analytics-ga.min.js'|// 'libs/analytics-ga.min.js'|g" "$CONFIG_FILE"
else
    echo "WARNING: Config file not found at $CONFIG_FILE"
fi

# Remove any custom config that might override
rm -f "$CONFIG_DIR/custom-config.js"
rm -f /home/ga/analytics_verification.png

# Restart Firefox to ensure clean state
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="