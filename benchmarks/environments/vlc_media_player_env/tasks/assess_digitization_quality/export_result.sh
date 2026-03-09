#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Assess Digitization Quality Result ==="

# Check for assessment report
REPORT_FILE="/home/ga/Documents/digitization_report.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Assessment report found: $REPORT_FILE"
    cp "$REPORT_FILE" /tmp/vlc_digitization_report.txt
    
    echo ""
    echo "=== Report Contents ==="
    cat "$REPORT_FILE"
    echo "======================="
    echo ""
else
    echo "⚠️ Assessment report not found at expected location: $REPORT_FILE"
    
    # Look for any recently created text files in Documents
    RECENT_DOC=$(find /home/ga/Documents -type f \( -name "*.txt" -o -name "*report*" \) -mmin -5 2>/dev/null | head -1)
    
    if [ -n "$RECENT_DOC" ]; then
        echo "Found recent document: $RECENT_DOC"
        cp "$RECENT_DOC" /tmp/vlc_digitization_report.txt
    else
        # Create empty file to avoid verification errors
        echo "No report found" > /tmp/vlc_digitization_report.txt
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

# Copy VLC config in case agent made aspect ratio changes
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_digitization_vlcrc.txt 2>/dev/null || true
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_digitization_completed.txt
echo "Digitization assessment task completed" >> /tmp/vlc_digitization_completed.txt

echo "✅ Export complete"
echo "=== Export Complete ==="