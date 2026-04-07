#!/bin/bash
# Export results for drivein_fm_broadcast_mastering task
set -e

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Music/fm_broadcast_audio.mp3"
BASELINE_FILE="/tmp/baseline_audio.mp3"

OUTPUT_EXISTS="false"
CREATED_DURING_TASK="false"
HAS_VIDEO="true"
CHANNELS=0
SAMPLE_RATE=0
CODEC="unknown"
MEAN_VOLUME=0
MAX_VOLUME=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Probe properties
    HAS_VIDEO=$(ffprobe -v error -select_streams v -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null | grep -q "video" && echo "true" || echo "false")
    
    AUDIO_INFO=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels,sample_rate,codec_name -of json "$OUTPUT_FILE" 2>/dev/null || echo "{}")
    CHANNELS=$(echo "$AUDIO_INFO" | grep -o '"channels": [0-9]*' | grep -o '[0-9]*' || echo "0")
    SAMPLE_RATE=$(echo "$AUDIO_INFO" | grep -o '"sample_rate": "[0-9]*"' | grep -o '[0-9]*' || echo "0")
    CODEC=$(echo "$AUDIO_INFO" | grep -o '"codec_name": "[^"]*"' | cut -d'"' -f4 || echo "unknown")

    # Measure acoustic properties (volumedetect)
    # This proves if the dynamic range compressor was actually applied
    VOL_DATA=$(ffmpeg -i "$OUTPUT_FILE" -af "volumedetect" -vn -sn -dn -f null /dev/null 2>&1 | grep "volume:")
    MEAN_VOLUME=$(echo "$VOL_DATA" | grep "mean_volume:" | grep -oEo '[-+0-9.]+' | head -1 || echo "0")
    MAX_VOLUME=$(echo "$VOL_DATA" | grep "max_volume:" | grep -oEo '[-+0-9.]+' | head -1 || echo "0")
fi

# Measure baseline acoustic properties
BASE_MEAN_VOLUME=0
BASE_MAX_VOLUME=0
if [ -f "$BASELINE_FILE" ]; then
    BASE_VOL_DATA=$(ffmpeg -i "$BASELINE_FILE" -af "volumedetect" -vn -sn -dn -f null /dev/null 2>&1 | grep "volume:")
    BASE_MEAN_VOLUME=$(echo "$BASE_VOL_DATA" | grep "mean_volume:" | grep -oEo '[-+0-9.]+' | head -1 || echo "0")
    BASE_MAX_VOLUME=$(echo "$BASE_VOL_DATA" | grep "max_volume:" | grep -oEo '[-+0-9.]+' | head -1 || echo "0")
fi

# Check JSON spec
SPEC_FILE="/home/ga/Documents/fm_specs.json"
SPEC_EXISTS="false"
SPEC_CONTENT="{}"
if [ -f "$SPEC_FILE" ]; then
    SPEC_EXISTS="true"
    # Read the first 1000 characters to prevent huge injections, escape quotes
    SPEC_CONTENT=$(head -c 1000 "$SPEC_FILE" | jq -c '.' 2>/dev/null || echo "{\"error\": \"invalid_json\"}")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "has_video": $HAS_VIDEO,
    "channels": ${CHANNELS:-0},
    "sample_rate": ${SAMPLE_RATE:-0},
    "codec": "$CODEC",
    "mean_volume_db": ${MEAN_VOLUME:-0},
    "max_volume_db": ${MAX_VOLUME:-0},
    "base_mean_volume_db": ${BASE_MEAN_VOLUME:-0},
    "base_max_volume_db": ${BASE_MAX_VOLUME:-0},
    "spec_exists": $SPEC_EXISTS,
    "spec_content": $SPEC_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="