#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Playback Issue Result ==="

# Check for diagnostic report at expected location
EXPECTED_REPORT="/home/ga/Documents/diagnostic_report.txt"
REPORT_FOUND="false"

if [ -f "$EXPECTED_REPORT" ]; then
    echo "✅ Diagnostic report found: $EXPECTED_REPORT"
    cp "$EXPECTED_REPORT" /tmp/diagnostic_report.txt
    REPORT_FOUND="true"
    echo "--- Report Contents ---"
    cat "$EXPECTED_REPORT"
    echo "--- End Report ---"
else
    echo "⚠️ Expected diagnostic report not found at $EXPECTED_REPORT"
    
    # Look for any recently created text files in Documents that might be the report
    RECENT_REPORT=$(find /home/ga/Documents -name "*.txt" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_REPORT" ]; then
        echo "Found recent text file: $RECENT_REPORT"
        cp "$RECENT_REPORT" /tmp/diagnostic_report.txt
        REPORT_FOUND="true"
        echo "--- Report Contents ---"
        cat "$RECENT_REPORT"
        echo "--- End Report ---"
    else
        echo "❌ No diagnostic report found"
        # Create empty report for verifier to handle
        touch /tmp/diagnostic_report.txt
        echo "No report generated" > /tmp/diagnostic_report.txt
    fi
fi

# Also capture the problem video info for verification
if [ -f "/home/ga/Videos/problem_video.mkv" ]; then
    ffprobe -v error -show_format -show_streams -of json \
        /home/ga/Videos/problem_video.mkv > /tmp/problem_video_metadata.json 2>&1 || true
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
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
cat > /tmp/vlc_diagnose_completed.txt <<EOF
$(date)
Diagnose playback issue task completed
Report found: $REPORT_FOUND
EOF

echo "=== Export Complete ==="