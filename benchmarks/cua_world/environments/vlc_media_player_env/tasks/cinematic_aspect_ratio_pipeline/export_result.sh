#!/bin/bash
# Export script for cinematic_aspect_ratio_pipeline task
set -e

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create temporary JSON output
TEMP_JSON=$(mktemp /tmp/aspect_results.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"outputs\": {" >> "$TEMP_JSON"

# Target output files
FILES=("cinemascope.mp4" "academy_flat.mp4" "classic_tv.mp4" "square_social.mp4" "vertical_mobile.mp4")
FIRST=true

for file in "${FILES[@]}"; do
    PATH="/home/ga/Videos/aspect_ratios/$file"
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "    ," >> "$TEMP_JSON"
    fi
    
    echo "    \"$file\": {" >> "$TEMP_JSON"
    
    if [ -f "$PATH" ]; then
        MTIME=$(stat -c %Y "$PATH" 2>/dev/null || echo "0")
        SIZE=$(stat -c %s "$PATH" 2>/dev/null || echo "0")
        
        # Get video/audio metadata using ffprobe
        V_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$PATH" 2>/dev/null || echo "unknown")
        WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$PATH" 2>/dev/null || echo "0")
        HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$PATH" 2>/dev/null || echo "0")
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$PATH" 2>/dev/null || echo "0")
        
        # Audio check
        A_CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$PATH" 2>/dev/null || echo "none")
        A_CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$PATH" 2>/dev/null || echo "0")

        echo "      \"exists\": true," >> "$TEMP_JSON"
        echo "      \"mtime\": $MTIME," >> "$TEMP_JSON"
        echo "      \"size_bytes\": $SIZE," >> "$TEMP_JSON"
        echo "      \"video_codec\": \"$V_CODEC\"," >> "$TEMP_JSON"
        echo "      \"width\": $WIDTH," >> "$TEMP_JSON"
        echo "      \"height\": $HEIGHT," >> "$TEMP_JSON"
        echo "      \"duration\": $DURATION," >> "$TEMP_JSON"
        echo "      \"audio_codec\": \"$A_CODEC\"," >> "$TEMP_JSON"
        echo "      \"audio_channels\": $A_CHANNELS" >> "$TEMP_JSON"
    else
        echo "      \"exists\": false" >> "$TEMP_JSON"
    fi
    echo "    }" >> "$TEMP_JSON"
done

echo "  }" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Safely copy results to known location for the verifier
rm -f /tmp/aspect_ratio_results.json 2>/dev/null || sudo rm -f /tmp/aspect_ratio_results.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aspect_ratio_results.json
chmod 666 /tmp/aspect_ratio_results.json

# Copy the catalog file if it exists so the verifier can read it
if [ -f "/home/ga/Videos/aspect_ratios/aspect_catalog.json" ]; then
    cp "/home/ga/Videos/aspect_ratios/aspect_catalog.json" /tmp/aspect_catalog.json 2>/dev/null || true
    chmod 666 /tmp/aspect_catalog.json 2>/dev/null || true
fi

rm -f "$TEMP_JSON"

echo "Results exported to /tmp/aspect_ratio_results.json"
echo "=== Export complete ==="