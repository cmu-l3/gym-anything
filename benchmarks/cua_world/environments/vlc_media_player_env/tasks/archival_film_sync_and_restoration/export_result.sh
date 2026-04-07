#!/bin/bash
echo "=== Exporting Archival Restoration Result ==="
source /workspace/scripts/task_utils.sh

# Record task end
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Videos/restored_archive.mp4"
REPORT_FILE="/home/ga/Documents/restoration_log.json"

# Initialize variables
OUTPUT_EXISTS="false"
REPORT_EXISTS="false"
OUTPUT_SIZE="0"
CREATED_DURING_TASK="false"
DAR=""
WIDTH=""
HEIGHT=""
PROG_FRAMES="0"
TFF_FRAMES="0"

# 1. Process Video Output
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Extract Metadata
    DAR=$(ffprobe -v error -select_streams v:0 -show_entries stream=display_aspect_ratio -of csv=p=0 "$OUTPUT_FILE" 2>/dev/null || echo "")
    WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUTPUT_FILE" 2>/dev/null || echo "0")
    HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Extract audio stream as WAV for perfect host-side sync verification via scipy
    echo "Extracting audio for analysis..."
    ffmpeg -y -i "$OUTPUT_FILE" -acodec pcm_s16le -ac 1 -ar 44100 /tmp/restored_audio.wav 2>/dev/null || true
    
    # Perform in-container interlacing analysis using idet filter
    echo "Running IDET interlace detection..."
    ffmpeg -i "$OUTPUT_FILE" -vf idet -f null - 2> /tmp/idet_log.txt || true
    if [ -f /tmp/idet_log.txt ]; then
        PROG_FRAMES=$(grep -o "Multi frame detection: TFF:[ ]*[0-9]* BFF:[ ]*[0-9]* Progressive:[ ]*[0-9]*" /tmp/idet_log.txt | grep -o "Progressive:[ ]*[0-9]*" | awk -F':' '{print $2}' | tr -d ' ' || echo "0")
        TFF_FRAMES=$(grep -o "Multi frame detection: TFF:[ ]*[0-9]* BFF:[ ]*[0-9]* Progressive:[ ]*[0-9]*" /tmp/idet_log.txt | grep -o "TFF:[ ]*[0-9]*" | awk -F':' '{print $2}' | tr -d ' ' || echo "0")
    fi
fi

# 2. Process JSON Report
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    cp "$REPORT_FILE" /tmp/restoration_log.json 2>/dev/null
fi

# 3. Create Status Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "dar": "$DAR",
    "width": "$WIDTH",
    "height": "$HEIGHT",
    "prog_frames": $PROG_FRAMES,
    "tff_frames": $TFF_FRAMES
}
EOF

# Move status securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
[ -f /tmp/restored_audio.wav ] && chmod 666 /tmp/restored_audio.wav 2>/dev/null || true
[ -f /tmp/restoration_log.json ] && chmod 666 /tmp/restoration_log.json 2>/dev/null || true
rm -f "$TEMP_JSON"

kill_vlc "ga"
echo "Result payload saved."
cat /tmp/task_result.json
echo "=== Export complete ==="