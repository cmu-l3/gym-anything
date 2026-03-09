#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Normalize Podcast Audio Result ==="

NORM_DIR="/home/ga/podcast_project/normalized"

# Check for normalized files
echo "Checking for normalized audio files..."

EXPECTED_FILES=(
    "normalized_segment_intro.mp3"
    "normalized_segment_interview.mp3"
    "normalized_segment_outro.mp3"
)

FILES_FOUND=0
for filename in "${EXPECTED_FILES[@]}"; do
    filepath="${NORM_DIR}/${filename}"
    if [ -f "$filepath" ]; then
        echo "✅ Found: $filename"
        cp "$filepath" "/tmp/${filename}"
        FILES_FOUND=$((FILES_FOUND + 1))
    else
        echo "⚠️  Missing: $filename"
    fi
done

echo ""
echo "Files found: $FILES_FOUND / ${#EXPECTED_FILES[@]}"

# If some files exist, analyze their audio levels
if [ $FILES_FOUND -gt 0 ]; then
    echo ""
    echo "Analyzing normalized audio levels:"
    for filename in "${EXPECTED_FILES[@]}"; do
        tmpfile="/tmp/${filename}"
        if [ -f "$tmpfile" ]; then
            echo -n "  $filename: "
            ffmpeg -i "$tmpfile" -af "volumedetect" -f null /dev/null 2>&1 | grep "max_volume" | awk '{print $5, $6}' || echo "analysis failed"
        fi
    done
fi

# List all files in normalized directory for debugging
echo ""
echo "Contents of normalized directory:"
ls -lh "$NORM_DIR/" 2>/dev/null || echo "  (directory empty or not found)"

# Close VLC if running
if is_vlc_running; then
    echo ""
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_normalize_completed.txt
echo "Files found: $FILES_FOUND" >> /tmp/vlc_normalize_completed.txt

echo ""
echo "=== Export Complete ==="