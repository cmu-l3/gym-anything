#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Detect Audio Clipping Result ==="

ANALYSIS_FILE="/home/ga/Music/recordings/guitar_take_01_analysis.txt"

# Check if analysis file exists
if [ -f "$ANALYSIS_FILE" ]; then
    echo "✅ Analysis file found: $ANALYSIS_FILE"
    cp "$ANALYSIS_FILE" /tmp/vlc_clipping_analysis.txt
    echo "--- Analysis Content ---"
    cat "$ANALYSIS_FILE"
    echo "--- End Analysis ---"
else
    echo "⚠️ Analysis file not found at expected location"
    
    # Look for any recently created text file in recordings directory
    RECENT_TXT=$(find /home/ga/Music/recordings -name "*.txt" -type f -mmin -5 2>/dev/null | head -1)
    
    if [ -n "$RECENT_TXT" ]; then
        echo "Found recent text file: $RECENT_TXT"
        cp "$RECENT_TXT" /tmp/vlc_clipping_analysis.txt
        echo "--- Content ---"
        cat "$RECENT_TXT"
        echo "--- End ---"
    else
        echo "No analysis file found"
        # Create empty placeholder
        echo "ERROR: No analysis file created" > /tmp/vlc_clipping_analysis.txt
    fi
fi

# Copy ground truth for verifier
if [ -f "/tmp/clipping_ground_truth.json" ]; then
    cp "/tmp/clipping_ground_truth.json" /tmp/vlc_clipping_ground_truth.json
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

echo "$(date)" > /tmp/vlc_clipping_completed.txt
echo "Audio clipping detection task completed" >> /tmp/vlc_clipping_completed.txt

echo "=== Export Complete ==="