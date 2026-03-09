#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Lecture Highlights Result ==="

OUTPUT_DIR="/home/ga/Music/lecture_highlights"
EXPECTED_FILES=(
    "segment_1_concept_a.mp3"
    "segment_2_concept_b.mp3"
    "segment_3_concept_c.mp3"
    "segment_4_concept_d.mp3"
)

# Check which files were created
FILES_FOUND=0
FILES_INFO="{"

for i in "${!EXPECTED_FILES[@]}"; do
    filename="${EXPECTED_FILES[$i]}"
    filepath="$OUTPUT_DIR/$filename"
    
    if [ -f "$filepath" ]; then
        FILES_FOUND=$((FILES_FOUND + 1))
        filesize=$(stat -c%s "$filepath")
        echo "✅ Found: $filename ($(numfmt --to=iec-i --suffix=B $filesize))"
        
        # Copy to /tmp for verification
        cp "$filepath" "/tmp/vlc_segment_${i}.mp3"
        
        # Add to JSON
        [ $i -gt 0 ] && FILES_INFO="${FILES_INFO},"
        FILES_INFO="${FILES_INFO}\"${filename}\": {\"found\": true, \"size\": ${filesize}}"
    else
        echo "❌ Missing: $filename"
        
        # Add to JSON
        [ $i -gt 0 ] && FILES_INFO="${FILES_INFO},"
        FILES_INFO="${FILES_INFO}\"${filename}\": {\"found\": false}"
    fi
done

FILES_INFO="${FILES_INFO}}"

# Create result summary JSON
cat > /tmp/vlc_extract_highlights_result.json <<EOF
{
    "files_found": $FILES_FOUND,
    "expected_files": ${#EXPECTED_FILES[@]},
    "files_info": $FILES_INFO,
    "output_directory": "$OUTPUT_DIR"
}
EOF

echo ""
echo "Summary: $FILES_FOUND/${#EXPECTED_FILES[@]} files found"
cat /tmp/vlc_extract_highlights_result.json

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Cleanup: kill any remaining VLC or ffmpeg processes
pkill -u ga vlc 2>/dev/null || true
pkill -u ga cvlc 2>/dev/null || true

echo "$(date)" > /tmp/vlc_extract_highlights_completed.txt
echo "Extract highlights task completed" >> /tmp/vlc_extract_highlights_completed.txt
echo "Files extracted: $FILES_FOUND/${#EXPECTED_FILES[@]}" >> /tmp/vlc_extract_highlights_completed.txt

echo "=== Export Complete ==="