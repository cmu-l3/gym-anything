#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Salvage Corrupted Video Result ==="

# Check for recovered video at expected location
EXPECTED_OUTPUT="/home/ga/Videos/recovered/interview_salvaged.mp4"
OUTPUT_COPIED=false

if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "✅ Recovered video found at expected location: $EXPECTED_OUTPUT"
    cp "$EXPECTED_OUTPUT" /tmp/vlc_salvaged_video.mp4
    OUTPUT_COPIED=true
    ls -lh "$EXPECTED_OUTPUT"
else
    echo "⚠️ Recovered video not found at expected location"
    
    # Look for any recently created video files in recovered directory
    RECOVERED_DIR="/home/ga/Videos/recovered"
    if [ -d "$RECOVERED_DIR" ]; then
        # Find files modified in last 10 minutes
        RECENT_VIDEO=$(find "$RECOVERED_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 2>/dev/null | head -1)
        
        if [ -n "$RECENT_VIDEO" ]; then
            echo "Found recent video in recovered directory: $RECENT_VIDEO"
            cp "$RECENT_VIDEO" /tmp/vlc_salvaged_video.mp4
            OUTPUT_COPIED=true
        fi
    fi
    
    # Last resort: check Downloads or Videos directories
    if [ "$OUTPUT_COPIED" = false ]; then
        for dir in "/home/ga/Downloads" "/home/ga/Videos"; do
            RECENT_VIDEO=$(find "$dir" -type f \( -name "*salvage*" -o -name "*recover*" -o -name "*interview*" \) -mmin -10 2>/dev/null | head -1)
            if [ -n "$RECENT_VIDEO" ]; then
                echo "Found potential recovered video: $RECENT_VIDEO"
                cp "$RECENT_VIDEO" /tmp/vlc_salvaged_video.mp4
                OUTPUT_COPIED=true
                break
            fi
        done
    fi
fi

# Copy corrupted input file for verification comparison
CORRUPTED_INPUT="/home/ga/Videos/corrupted/interview_incomplete.mp4"
if [ -f "$CORRUPTED_INPUT" ]; then
    cp "$CORRUPTED_INPUT" /tmp/vlc_corrupted_input.mp4
    echo "Copied corrupted input for verification"
fi

# Copy size metadata
if [ -f /tmp/vlc_salvage_original_size.txt ]; then
    cp /tmp/vlc_salvage_original_size.txt /tmp/vlc_salvage_sizes.txt
fi
if [ -f /tmp/vlc_salvage_corrupted_size.txt ]; then
    cat /tmp/vlc_salvage_corrupted_size.txt >> /tmp/vlc_salvage_sizes.txt
fi

# Create result summary
cat > /tmp/vlc_salvage_summary.json <<EOF
{
    "output_found": $OUTPUT_COPIED,
    "expected_path": "$EXPECTED_OUTPUT",
    "output_exists": $([ -f "$EXPECTED_OUTPUT" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result summary:"
cat /tmp/vlc_salvage_summary.json

# Close VLC (may take time if conversion is still running)
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try graceful close first
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3
    
    # Force kill if still running
    if is_vlc_running; then
        echo "VLC still running, force closing..."
        kill_vlc ga
        sleep 1
    fi
fi

echo "$(date)" > /tmp/vlc_salvage_completed.txt
echo "Salvage corrupted video task completed" >> /tmp/vlc_salvage_completed.txt
echo "Output copied: $OUTPUT_COPIED" >> /tmp/vlc_salvage_completed.txt

echo "=== Export Complete ==="