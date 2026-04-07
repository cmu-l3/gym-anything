#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Vinyl Album Sequencing Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    # Bring to foreground, send Ctrl+S to save
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read baseline
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check for exported master file
EXPORT_DIR="/home/ga/Audio/vinyl_delivery"
SESSION_EXPORT_DIR="/home/ga/Audio/sessions/MyProject/export"

EXPORTED_FILE=""
EXPORTED_FILE_SIZE=0
EXPORTED_FILE_MTIME=0

# First check requested delivery folder
if [ -d "$EXPORT_DIR" ]; then
    FOUND=$(find "$EXPORT_DIR" -name "*.wav" -type f | head -1)
    if [ -n "$FOUND" ]; then
        EXPORTED_FILE="$FOUND"
    fi
fi

# Fallback to session export directory
if [ -z "$EXPORTED_FILE" ] && [ -d "$SESSION_EXPORT_DIR" ]; then
    FOUND=$(find "$SESSION_EXPORT_DIR" -name "*.wav" -type f | head -1)
    if [ -n "$FOUND" ]; then
        EXPORTED_FILE="$FOUND"
    fi
fi

if [ -n "$EXPORTED_FILE" ]; then
    EXPORTED_FILE_SIZE=$(stat -c %s "$EXPORTED_FILE" 2>/dev/null || echo "0")
    EXPORTED_FILE_MTIME=$(stat -c %Y "$EXPORTED_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/vinyl_sequencing_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "task_start_timestamp": $TASK_START,
    "exported_file": "$EXPORTED_FILE",
    "exported_file_size": $EXPORTED_FILE_SIZE,
    "exported_file_mtime": $EXPORTED_FILE_MTIME,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/vinyl_sequencing_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/vinyl_sequencing_result.json
chmod 666 /tmp/vinyl_sequencing_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/vinyl_sequencing_result.json"
echo "=== Export Complete ==="