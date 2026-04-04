#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Batch Verify Raw Footage Result ==="

# Export the QA report
QA_REPORT="/home/ga/Documents/qa_report.txt"

if [ -f "$QA_REPORT" ]; then
    echo "✅ QA report found: $QA_REPORT"
    cp "$QA_REPORT" /tmp/vlc_batch_qa_report.txt
    echo ""
    echo "Report contents:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$QA_REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "⚠️ QA report not found at expected location"
    
    # Look for any text files in Documents that might be the report
    RECENT_TXT=$(find /home/ga/Documents -name "*.txt" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_TXT" ]; then
        echo "Found recent text file: $RECENT_TXT"
        cp "$RECENT_TXT" /tmp/vlc_batch_qa_report.txt
    else
        echo "No report found - creating empty marker file"
        echo "NO REPORT GENERATED" > /tmp/vlc_batch_qa_report.txt
    fi
fi

# Also export any additional documentation files
if [ -d /home/ga/Documents ]; then
    find /home/ga/Documents -name "*.txt" -o -name "*.md" -mmin -10 2>/dev/null | while read file; do
        if [ "$file" != "$QA_REPORT" ]; then
            basename_file=$(basename "$file")
            cp "$file" "/tmp/vlc_batch_extra_${basename_file}" 2>/dev/null || true
        fi
    done
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_batch_verify_completed.txt
echo "Batch QA verification task completed" >> /tmp/vlc_batch_verify_completed.txt
echo "Report path: $QA_REPORT" >> /tmp/vlc_batch_verify_completed.txt

# Export the test videos for verification (optional, for debugging)
# We'll export metadata instead to save space
echo "Exporting video metadata for verification..."
for file in ceremony_01.mp4 ceremony_02.mp4 reception_speeches.mp4 first_dance.mp4 venue_broll.mp4; do
    filepath="/home/ga/Videos/wedding_raw/$file"
    if [ -f "$filepath" ]; then
        echo "Metadata for $file:" >> /tmp/vlc_batch_video_metadata.txt
        ffprobe -v error -show_entries stream=codec_name,width,height:format=duration \
                -of default=noprint_wrappers=1:nokey=0 "$filepath" 2>&1 >> /tmp/vlc_batch_video_metadata.txt || true
        echo "---" >> /tmp/vlc_batch_video_metadata.txt
    fi
done

echo "=== Export Complete ==="