#!/bin/bash
echo "=== Exporting Fitness Circuit Stations Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/circuit_training_stations.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/circuit_training_stations.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content flags
HAS_TITLE="false"      # "Circuit Training"
HAS_SAFETY="false"     # "Warm up"
HAS_STATION1="false"   # "Jumping Jacks"
HAS_STATION2="false"   # "Wall Sit"
HAS_STATION3="false"   # "Push" (Push-Ups)
HAS_REPS="false"       # "30", "45", "15" (checking for at least 2)

# Shape counts
CIRCLE_COUNT=0

# Check primary path, then alt
if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")

    # Validate file format
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check anti-gaming timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Content Analysis: Unzip and grep XML
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Check text requirements
        if echo "$ALL_TEXT" | grep -qi "Circuit Training"; then HAS_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Warm up"; then HAS_SAFETY="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Jumping Jacks"; then HAS_STATION1="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Wall Sit"; then HAS_STATION2="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Push"; then HAS_STATION3="true"; fi
        
        # Check for numbers (reps/time)
        MATCH_COUNT=0
        if echo "$ALL_TEXT" | grep -q "30"; then MATCH_COUNT=$((MATCH_COUNT+1)); fi
        if echo "$ALL_TEXT" | grep -q "45"; then MATCH_COUNT=$((MATCH_COUNT+1)); fi
        if echo "$ALL_TEXT" | grep -q "15"; then MATCH_COUNT=$((MATCH_COUNT+1)); fi
        if [ "$MATCH_COUNT" -ge 2 ]; then HAS_REPS="true"; fi

        # Check for shapes (Circles/Ellipses)
        # Search for XML tags or attributes indicating circle shapes
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            C=$(grep -ic 'AsCircle\|AsEllipse\|AsOval\|type="Circle"\|type="Ellipse"\|shapeType="Circle"\|shapeType="Ellipse"' "$XML_FILE" 2>/dev/null || echo 0)
            CIRCLE_COUNT=$((CIRCLE_COUNT + C))
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Write JSON result using Python to ensure valid format
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "has_title": $HAS_TITLE,
    "has_safety": $HAS_SAFETY,
    "has_station1": $HAS_STATION1,
    "has_station2": $HAS_STATION2,
    "has_station3": $HAS_STATION3,
    "has_reps": $HAS_REPS,
    "circle_count": $CIRCLE_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export Complete ==="