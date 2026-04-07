#!/bin/bash
echo "=== Exporting Esports VOD Highlight Packaging Results ==="

# Record end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract media analysis using ffprobe (done inside container to guarantee tool availability)
echo "Analyzing output files..."

JSON_OUTPUT="/tmp/ffprobe_results.json"
echo "{" > $JSON_OUTPUT

# Define target files
FILES=("highlight_1_ambush.mp4" "highlight_2_defense.mp4" "highlight_3_victory.mp4")
FIRST=true

for file in "${FILES[@]}"; do
    FILE_PATH="/home/ga/Videos/social_highlights/$file"
    
    if [ ! "$FIRST" = true ]; then
        echo "," >> $JSON_OUTPUT
    fi
    FIRST=false
    
    echo "\"$file\": {" >> $JSON_OUTPUT
    
    if [ -f "$FILE_PATH" ]; then
        FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            CREATED_DURING="true"
        else
            CREATED_DURING="false"
        fi
        
        # Run ffprobe to get video/audio info
        FFPROBE_DATA=$(ffprobe -v error -show_format -show_streams -of json "$FILE_PATH" 2>/dev/null || echo "{}")
        
        echo "\"exists\": true," >> $JSON_OUTPUT
        echo "\"created_during_task\": $CREATED_DURING," >> $JSON_OUTPUT
        echo "\"size_bytes\": $FILE_SIZE," >> $JSON_OUTPUT
        echo "\"ffprobe\": $FFPROBE_DATA" >> $JSON_OUTPUT
    else
        echo "\"exists\": false" >> $JSON_OUTPUT
    fi
    
    echo "}" >> $JSON_OUTPUT
done

echo "}" >> $JSON_OUTPUT

# 3. Copy Manifest safely
if [ -f "/home/ga/Videos/social_highlights/manifest.json" ]; then
    cp "/home/ga/Videos/social_highlights/manifest.json" "/tmp/manifest_exported.json"
else
    echo "{}" > "/tmp/manifest_exported.json"
fi

# Ensure permissions
chmod 666 /tmp/ffprobe_results.json
chmod 666 /tmp/manifest_exported.json

echo "Results exported."
echo "=== Export Complete ==="