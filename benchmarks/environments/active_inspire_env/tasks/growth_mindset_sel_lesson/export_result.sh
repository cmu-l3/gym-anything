#!/bin/bash
# Export script for Growth Mindset SEL Lesson task
# Extracts verification data from the agent's created flipchart.

echo "=== Exporting Growth Mindset SEL Lesson Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/growth_mindset_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/growth_mindset_lesson.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Text content flags
HAS_TITLE="false"
HAS_SUBTITLE="false"
HAS_FIXED_TITLE="false"
HAS_YET_TITLE="false"
HAS_GOAL_TITLE="false"
HAS_GOAL_PROMPT="false"

# Phrase counters
FIXED_PHRASES_FOUND=0
GROWTH_PHRASES_FOUND=0

# Shape counters
CIRCLE_COUNT=0
LINE_COUNT=0
ARROW_COUNT=0
STAR_COUNT=0
TOTAL_SHAPE_COUNT=0

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

    # Validate flipchart format
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check creation time vs task start
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then

        # Collect text from all XML files
        ALL_TEXT=""
        # Iterate safely
        while IFS= read -r -d '' XML_FILE; do
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done < <(find "$TMP_DIR" -name "*.xml" -print0)

        # --- Text Content Checks ---
        # Page 1
        if echo "$ALL_TEXT" | grep -qi "Growth Mindset"; then HAS_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "believe.*can grow\|grow.*believe"; then HAS_SUBTITLE="true"; fi
        
        # Page 2
        if echo "$ALL_TEXT" | grep -qi "Fixed Mindset"; then HAS_FIXED_TITLE="true"; fi
        
        # Fixed phrases count
        if echo "$ALL_TEXT" | grep -qi "can't do this\|cannot do this"; then ((FIXED_PHRASES_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -qi "too hard"; then ((FIXED_PHRASES_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -qi "give up"; then ((FIXED_PHRASES_FOUND++)); fi
        
        # Growth phrases count
        if echo "$ALL_TEXT" | grep -qi "yet"; then ((GROWTH_PHRASES_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -qi "challenge"; then ((GROWTH_PHRASES_FOUND++)); fi
        if echo "$ALL_TEXT" | grep -qi "strategy\|strategies"; then ((GROWTH_PHRASES_FOUND++)); fi
        
        # Page 3
        if echo "$ALL_TEXT" | grep -qi "Power of Yet\|Power.*Yet"; then HAS_YET_TITLE="true"; fi
        
        # Page 4
        if echo "$ALL_TEXT" | grep -qi "Goal"; then HAS_GOAL_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "keep trying"; then HAS_GOAL_PROMPT="true"; fi

        # --- Shape Analysis ---
        # Scan all XML files for shape definitions
        while IFS= read -r -d '' XML_FILE; do
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                # Count Circles/Ovals
                C=$(grep -icE 'AsCircle|AsEllipse|AsOval|type="Circle"|type="Ellipse"|shapeType="Circle"|shapeType="Ellipse"' "$XML_FILE" || echo 0)
                CIRCLE_COUNT=$((CIRCLE_COUNT + C))
                
                # Count Lines
                L=$(grep -icE 'AsLine|type="Line"|shapeType="Line"' "$XML_FILE" || echo 0)
                LINE_COUNT=$((LINE_COUNT + L))
                
                # Count Arrows (Block arrows or lines with arrowheads)
                A=$(grep -icE 'AsArrow|type="Arrow"|shapeType="Arrow"|ArrowHead' "$XML_FILE" || echo 0)
                ARROW_COUNT=$((ARROW_COUNT + A))
                
                # Count Stars (Star5, Star, Polygon)
                S=$(grep -icE 'AsStar|type="Star"|shapeType="Star"|AsPolygon' "$XML_FILE" || echo 0)
                STAR_COUNT=$((STAR_COUNT + S))
                
                # Total generic shapes
                T=$(grep -icE 'AsShape|<Shape' "$XML_FILE" || echo 0)
                TOTAL_SHAPE_COUNT=$((TOTAL_SHAPE_COUNT + T))
            fi
        done < <(find "$TMP_DIR" -name "*.xml" -print0)
        
        # Adjust total if specific counts are higher (sometimes AsShape is generic)
        SUM_SPECIFIC=$((CIRCLE_COUNT + LINE_COUNT + ARROW_COUNT + STAR_COUNT))
        if [ "$SUM_SPECIFIC" -gt "$TOTAL_SHAPE_COUNT" ]; then
            TOTAL_SHAPE_COUNT="$SUM_SPECIFIC"
        fi
        
    fi
    rm -rf "$TMP_DIR"
fi

# Python script to safely write JSON
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": '$FILE_VALID' == 'true',
    "page_count": $PAGE_COUNT,
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "has_title": '$HAS_TITLE' == 'true',
    "has_subtitle": '$HAS_SUBTITLE' == 'true',
    "has_fixed_title": '$HAS_FIXED_TITLE' == 'true',
    "has_yet_title": '$HAS_YET_TITLE' == 'true',
    "has_goal_title": '$HAS_GOAL_TITLE' == 'true',
    "has_goal_prompt": '$HAS_GOAL_PROMPT' == 'true',
    "fixed_phrases_count": $FIXED_PHRASES_FOUND,
    "growth_phrases_count": $GROWTH_PHRASES_FOUND,
    "circle_count": $CIRCLE_COUNT,
    "line_count": $LINE_COUNT,
    "arrow_count": $ARROW_COUNT,
    "star_count": $STAR_COUNT,
    "total_shape_count": $TOTAL_SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written successfully")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="