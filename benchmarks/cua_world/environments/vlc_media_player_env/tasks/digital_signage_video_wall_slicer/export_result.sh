#!/bin/bash
echo "=== Exporting task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Videos/signage/wall_slices"
AGENT_FRAMES_DIR="/tmp/agent_frames"
mkdir -p "$AGENT_FRAMES_DIR"

# Initialize JSON array elements
PROBE_RESULTS=""

# Process each expected file
EXPECTED_FILES=("screen_1_left.mp4" "screen_2_center.mp4" "screen_3_right.mp4")

for i in "${!EXPECTED_FILES[@]}"; do
    FILE="$OUTPUT_DIR/${EXPECTED_FILES[$i]}"
    PREFIX=$(echo "${EXPECTED_FILES[$i]}" | cut -d'_' -f1-2) # e.g. "screen_1"
    
    EXISTS="false"
    SIZE=0
    WIDTH=0
    HEIGHT=0
    AUDIO_STREAMS=0
    MTIME=0
    
    if [ -f "$FILE" ]; then
        EXISTS="true"
        SIZE=$(stat -c %s "$FILE" 2>/dev/null || echo "0")
        MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
        
        # Probe video streams
        WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null || echo "0")
        HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null || echo "0")
        
        # Probe audio streams
        AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null | wc -l || echo "0")
        
        # Extract the middle frame (t=5s) for geometric comparison
        ffmpeg -y -ss 00:00:05 -i "$FILE" -vframes 1 "$AGENT_FRAMES_DIR/${PREFIX}.png" 2>/dev/null || true
    fi
    
    # Append to JSON array string
    FILE_JSON="\"${EXPECTED_FILES[$i]}\": {\"exists\": $EXISTS, \"size\": $SIZE, \"mtime\": $MTIME, \"width\": $WIDTH, \"height\": $HEIGHT, \"audio_streams\": $AUDIO_STREAMS}"
    if [ -z "$PROBE_RESULTS" ]; then
        PROBE_RESULTS="$FILE_JSON"
    else
        PROBE_RESULTS="$PROBE_RESULTS, $FILE_JSON"
    fi
done

# Prepare copies for verifier
cp "$OUTPUT_DIR/wall_test_playlist.xspf" /tmp/wall_test_playlist.xspf 2>/dev/null || true
cp "$OUTPUT_DIR/signage_manifest.json" /tmp/signage_manifest.json 2>/dev/null || true

# Copy ground truth frames to /tmp so copy_from_env can access them
mkdir -p /tmp/ground_truth
sudo cp /var/lib/app/ground_truth/*.png /tmp/ground_truth/ 2>/dev/null || true
sudo chmod 666 /tmp/ground_truth/*.png 2>/dev/null || true
sudo chmod 666 /tmp/agent_frames/*.png 2>/dev/null || true

# Construct final JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        $PROBE_RESULTS
    },
    "xspf_exists": $([ -f "$OUTPUT_DIR/wall_test_playlist.xspf" ] && echo "true" || echo "false"),
    "manifest_exists": $([ -f "$OUTPUT_DIR/signage_manifest.json" ] && echo "true" || echo "false")
}
EOF

# Make result JSON available
rm -f /tmp/signage_results.json 2>/dev/null || sudo rm -f /tmp/signage_results.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/signage_results.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/signage_results.json
chmod 666 /tmp/signage_results.json 2>/dev/null || sudo chmod 666 /tmp/signage_results.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="