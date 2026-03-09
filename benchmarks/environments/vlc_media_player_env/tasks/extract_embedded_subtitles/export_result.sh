#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Subtitles Result ==="

# Expected output file
EXPECTED_FILE="/home/ga/Videos/subtitles/extracted_english.srt"

# Check for extracted subtitle file
if [ -f "$EXPECTED_FILE" ]; then
    echo "✅ Extracted subtitle found: $EXPECTED_FILE"
    cp "$EXPECTED_FILE" /tmp/vlc_extracted_subtitle.srt
    
    # Show file info
    ls -lh "$EXPECTED_FILE"
    echo ""
    echo "First 20 lines of extracted subtitle:"
    head -20 "$EXPECTED_FILE" || true
else
    echo "⚠️ Expected subtitle file not found at: $EXPECTED_FILE"
    
    # Look for any recently created SRT files in the subtitles directory
    SUBTITLE_DIR="/home/ga/Videos/subtitles"
    if [ -d "$SUBTITLE_DIR" ]; then
        RECENT_SRT=$(find "$SUBTITLE_DIR" -name "*.srt" -type f -mmin -10 2>/dev/null | head -1)
        
        if [ -n "$RECENT_SRT" ]; then
            echo "Found recent SRT file: $RECENT_SRT"
            cp "$RECENT_SRT" /tmp/vlc_extracted_subtitle.srt
            ls -lh "$RECENT_SRT"
        else
            echo "No recently created SRT files in subtitles directory"
        fi
    fi
    
    # Check Videos directory as fallback
    if [ ! -f /tmp/vlc_extracted_subtitle.srt ]; then
        RECENT_SRT=$(find /home/ga/Videos -name "*.srt" -type f -mmin -10 2>/dev/null | grep -v "sample" | head -1)
        if [ -n "$RECENT_SRT" ]; then
            echo "Found recent SRT file in Videos: $RECENT_SRT"
            cp "$RECENT_SRT" /tmp/vlc_extracted_subtitle.srt
        else
            echo "❌ No recently created SRT files found"
            # Create empty marker so verifier knows task was attempted
            touch /tmp/vlc_extracted_subtitle.srt
        fi
    fi
fi

# Close VLC if still running
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Force kill if still running
if is_vlc_running; then
    echo "Force killing VLC..."
    kill_vlc ga
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_extract_subs_completed.txt
echo "Extract subtitles task export completed" >> /tmp/vlc_extract_subs_completed.txt

# Store metadata about the task
cat > /tmp/vlc_extract_subs_metadata.json <<EOF
{
    "expected_file": "$EXPECTED_FILE",
    "timestamp": "$(date -Iseconds)",
    "file_exists": $([ -f "$EXPECTED_FILE" ] && echo "true" || echo "false")
}
EOF

echo "=== Export Complete ==="