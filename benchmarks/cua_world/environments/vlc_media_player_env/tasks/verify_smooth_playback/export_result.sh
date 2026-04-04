#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Smooth Playback Result ==="

# Initialize statistics
DECODED_FRAMES=""
DISPLAYED_FRAMES=""
LOST_FRAMES=""
RUNTIME_CAPTURED="false"

# Try to query VLC RC interface for statistics
if is_vlc_running; then
    echo "Querying VLC RC interface for statistics..."
    
    # Get statistics from VLC
    RC_STATS=$(echo "stats" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_STATS" ]; then
        echo "RC Stats output:"
        echo "$RC_STATS"
        
        # Try to extract frame statistics
        DECODED_FRAMES=$(echo "$RC_STATS" | grep -oP '(?:decoded|input_decoded_):?\s*\K\d+' | head -1 || echo "")
        DISPLAYED_FRAMES=$(echo "$RC_STATS" | grep -oP '(?:displayed|output_decoded_):?\s*\K\d+' | head -1 || echo "")
        LOST_FRAMES=$(echo "$RC_STATS" | grep -oP '(?:lost|dropped):?\s*\K\d+' | head -1 || echo "")
        
        if [ -n "$DECODED_FRAMES" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured statistics from VLC RC"
            echo "  Decoded: $DECODED_FRAMES"
            echo "  Displayed: $DISPLAYED_FRAMES"
            echo "  Lost: $LOST_FRAMES"
        fi
    fi
fi

# Check for user-created report
REPORT_FILE="/home/ga/Documents/playback_stats.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ User report found: $REPORT_FILE"
    cp "$REPORT_FILE" /tmp/vlc_playback_report.txt
    echo "Report content:"
    cat "$REPORT_FILE"
else
    echo "⚠️ User report not found at $REPORT_FILE"
    
    # Check alternative locations
    for alt_path in "/home/ga/Documents/playback_report.txt" "/home/ga/Documents/stats.txt" "/home/ga/playback_stats.txt"; do
        if [ -f "$alt_path" ]; then
            echo "Found report at alternative location: $alt_path"
            cp "$alt_path" /tmp/vlc_playback_report.txt
            break
        fi
    done
    
    # If still no report and we captured runtime stats, create a fallback
    if [ "$RUNTIME_CAPTURED" = "true" ] && [ ! -f /tmp/vlc_playback_report.txt ]; then
        echo "Creating fallback report from runtime statistics..."
        cat > /tmp/vlc_playback_report.txt <<EOF
VLC Playback Statistics Report (Auto-generated)
===============================
File: sample_4k_test.mp4
Resolution: 3840x2160

Decoded frames: ${DECODED_FRAMES:-0}
Displayed frames: ${DISPLAYED_FRAMES:-0}
Dropped frames: ${LOST_FRAMES:-0}

Note: This report was auto-generated from VLC RC interface.
EOF
    fi
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

# Kill any remaining VLC processes
if is_vlc_running; then
    echo "Force killing VLC..."
    kill_vlc ga
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_playback_completed.txt
echo "Playback verification task completed" >> /tmp/vlc_playback_completed.txt

echo "=== Export Complete ==="