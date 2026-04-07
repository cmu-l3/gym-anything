#!/bin/bash
echo "=== Exporting Configure Dual Network Streams Result ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final State Screenshot (System-level)
take_screenshot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Check for Agent-Created Screenshot (Anti-gaming: created AFTER task start)
SCREENSHOT_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_PATH=""

# Find the most recent screenshot in the directory
LATEST_SCREENSHOT=$(find "$SCREENSHOT_DIR" -name "*.png" -o -name "*.jpg" 2>/dev/null | xargs ls -t 2>/dev/null | head -n 1)

if [ -n "$LATEST_SCREENSHOT" ]; then
    FILE_TIME=$(stat -c %Y "$LATEST_SCREENSHOT")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        AGENT_SCREENSHOT_EXISTS="true"
        AGENT_SCREENSHOT_PATH="$LATEST_SCREENSHOT"
        # Copy to /tmp for easier extraction if needed
        cp "$LATEST_SCREENSHOT" /tmp/agent_screenshot.png
    fi
fi

# 3. Check OpenBCI Process Status
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Check Network Activity (Programmatic verification of OSC stream)
# Check if any process is sending UDP packets to port 12345 or if the socket is open
# Since OSC is UDP connectionless, we check if the socket is bound/created by the java process
OSC_PORT_ACTIVE="false"
# lsof or netstat or ss can be used.
# Look for UDP sockets owned by the OpenBCI java process
OPENBCI_PID=$(pgrep -f "OpenBCI_GUI" | head -1)
if [ -n "$OPENBCI_PID" ]; then
    # Check if this PID has any UDP handles that might correspond to our stream
    # This is a heuristic; specific port binding might be ephemeral for sending
    # But often apps bind to 0.0.0.0 or a specific interface for sending
    if ss -lupn | grep "$OPENBCI_PID" | grep -q "12345"; then
        OSC_PORT_ACTIVE="true"
    elif ss -upn | grep "$OPENBCI_PID" | grep -q "12345"; then
         OSC_PORT_ACTIVE="true"
    fi
fi

# 5. Check Settings Files (Text-based verification)
# OpenBCI GUI v5 saves settings in JSON format in Documents/OpenBCI_GUI/Settings
# We search for recent files containing our target strings
SETTINGS_MATCH="false"
SETTINGS_FILE=""
# Find recently modified .json files in Settings
RECENT_SETTINGS=$(find /home/ga/Documents/OpenBCI_GUI/Settings -name "*.json" -mmin -10 2>/dev/null | head -1)

if [ -n "$RECENT_SETTINGS" ]; then
    SETTINGS_FILE="$RECENT_SETTINGS"
    # Check for keywords in the settings file
    if grep -q "Osc" "$RECENT_SETTINGS" && grep -q "12345" "$RECENT_SETTINGS"; then
        SETTINGS_MATCH="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_path": "$AGENT_SCREENSHOT_PATH",
    "osc_port_active": $OSC_PORT_ACTIVE,
    "settings_match": $SETTINGS_MATCH,
    "settings_file_path": "$SETTINGS_FILE",
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json