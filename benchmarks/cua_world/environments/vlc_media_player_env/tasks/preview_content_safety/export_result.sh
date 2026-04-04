#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Preview Content Safety Result ==="

# Check for review notes file
NOTES_FILE="/home/ga/Videos/content_review_notes.txt"

if [ -f "$NOTES_FILE" ]; then
    echo "✅ Review notes found: $NOTES_FILE"
    cp "$NOTES_FILE" /tmp/vlc_content_review_notes.txt
    echo "Content preview:"
    head -20 "$NOTES_FILE"
else
    echo "⚠️ Review notes file not found at expected location"
    
    # Search for any recently created text files in Videos directory
    RECENT_TXT=$(find /home/ga/Videos -name "*.txt" -type f -mmin -10 2>/dev/null | grep -v "CONTENT_PREVIEW_TASK" | head -1)
    
    if [ -n "$RECENT_TXT" ]; then
        echo "Found recent text file: $RECENT_TXT"
        cp "$RECENT_TXT" /tmp/vlc_content_review_notes.txt
    else
        # Create empty marker so verifier can provide feedback
        echo "No review notes file created" > /tmp/vlc_content_review_notes.txt
    fi
fi

# Export VLC config to check playback speed setting
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_preview_config.rc
    echo "✅ Exported VLC configuration"
    
    # Check for playback rate in config
    if grep -q "rate=" "$VLC_RC"; then
        RATE=$(grep "rate=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Playback rate found in config: ${RATE}x"
    fi
else
    echo "⚠️ VLC config not found"
fi

# Close VLC if running
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.5
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker with metadata
cat > /tmp/vlc_preview_completed.txt << EOF
$(date)
Task: Content Safety Preview
Video: wwii_doc_final_v3.mp4
Review notes: $([ -f "$NOTES_FILE" ] && echo "created" || echo "not found")
EOF

echo "✅ Export complete"
echo "=== Export Complete ==="