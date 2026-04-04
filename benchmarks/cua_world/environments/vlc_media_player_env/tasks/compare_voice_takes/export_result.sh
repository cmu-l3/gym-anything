#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Voice Takes Result ==="

# Path to selection document
SELECTION_FILE="/home/ga/VoiceRecordings/ProjectApollo/take_selection.txt"
RESULT_FILE="/tmp/vlc_voice_takes_selection.txt"

# Check if selection document exists
if [ -f "$SELECTION_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$SELECTION_FILE" 2>/dev/null || stat -c%s "$SELECTION_FILE" 2>/dev/null)
    echo "✅ Selection document found: $SELECTION_FILE (${FILE_SIZE} bytes)"
    
    # Copy to result location
    cp "$SELECTION_FILE" "$RESULT_FILE"
    
    # Show preview of content
    echo "--- Selection Document Preview ---"
    head -n 20 "$SELECTION_FILE"
    echo "--- End Preview ---"
else
    echo "⚠️ Selection document not found at expected location"
    
    # Create empty result file to indicate missing
    echo "MISSING: Selection document was not created" > "$RESULT_FILE"
fi

# Close VLC if running
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_voice_takes_completed.txt
echo "Voice takes comparison task completed" >> /tmp/vlc_voice_takes_completed.txt

if [ -f "$SELECTION_FILE" ]; then
    echo "Selection document size: $(stat -f%z "$SELECTION_FILE" 2>/dev/null || stat -c%s "$SELECTION_FILE" 2>/dev/null) bytes" >> /tmp/vlc_voice_takes_completed.txt
fi

echo "=== Export Complete ==="