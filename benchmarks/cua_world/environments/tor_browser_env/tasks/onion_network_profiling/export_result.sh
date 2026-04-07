#!/bin/bash
# export_result.sh for onion_network_profiling
set -e

echo "=== Exporting onion_network_profiling results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Documents/OnionProfiling"
CLEARNET_HAR="$OUTPUT_DIR/check_clearnet.har"
ONION_HAR="$OUTPUT_DIR/ddg_onion.har"

# Check for clearnet HAR
CLEARNET_EXISTS="false"
CLEARNET_SIZE=0
if [ -f "$CLEARNET_HAR" ]; then
    CLEARNET_EXISTS="true"
    CLEARNET_SIZE=$(stat -c %s "$CLEARNET_HAR" 2>/dev/null || echo "0")
    # Copy to tmp for copy_from_env
    cp "$CLEARNET_HAR" /tmp/check_clearnet.har 2>/dev/null || true
    chmod 666 /tmp/check_clearnet.har 2>/dev/null || true
fi

# Check for onion HAR
ONION_EXISTS="false"
ONION_SIZE=0
if [ -f "$ONION_HAR" ]; then
    ONION_EXISTS="true"
    ONION_SIZE=$(stat -c %s "$ONION_HAR" 2>/dev/null || echo "0")
    # Copy to tmp for copy_from_env
    cp "$ONION_HAR" /tmp/ddg_onion.har 2>/dev/null || true
    chmod 666 /tmp/ddg_onion.har 2>/dev/null || true
fi

# Check Tor Browser running state
TOR_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "clearnet_har_exists": $CLEARNET_EXISTS,
    "clearnet_har_size": $CLEARNET_SIZE,
    "onion_har_exists": $ONION_EXISTS,
    "onion_har_size": $ONION_SIZE,
    "tor_browser_running": $TOR_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json