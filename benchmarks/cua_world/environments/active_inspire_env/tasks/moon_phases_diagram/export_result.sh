#!/bin/bash
# Export script for Moon Phases Diagram task
# Extracts verification data from the agent's created flipchart

echo "=== Exporting Moon Phases Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/moon_phases_lesson.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/moon_phases_lesson.flp"

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
HAS_TITLE="false"
HAS_DURATION="false"
HAS_SUN="false"
HAS_EARTH="false"
HAS_ACTIVITY="false"
HAS_ORDER_TERM="false"

# Phase counts
PHASE_COUNT=0
FOUND_PHASES=""

# Shape count
SHAPE_COUNT=0

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

    # Check creation time vs task start
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for deep analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Consolidate all text from XMLs for easier searching
        # Note: In a real flipchart, page content is in individual XML files (page001.xml, etc.)
        # We need to search across all of them to find terms.
        
        # 1. Text Analysis
        ALL_TEXT=$(grep -rIh "<text" "$TMP_DIR" 2>/dev/null | sed 's/<[^>]*>//g')
        # If simple grep fails, try catting all XMLs
        if [ -z "$ALL_TEXT" ]; then
            ALL_TEXT=$(cat "$TMP_DIR"/*.xml 2>/dev/null)
        fi

        # Check Page 1 terms
        if echo "$ALL_TEXT" | grep -qi "Moon Phases"; then HAS_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qiE "29\.5|29 days"; then HAS_DURATION="true"; fi

        # Check Page 3 terms
        if echo "$ALL_TEXT" | grep -qi "Sun"; then HAS_SUN="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Earth"; then HAS_EARTH="true"; fi

        # Check Page 4 terms
        if echo "$ALL_TEXT" | grep -qiE "Activity|Challenge"; then HAS_ACTIVITY="true"; fi
        if echo "$ALL_TEXT" | grep -qiE "order|sequence"; then HAS_ORDER_TERM="true"; fi

        # Check Phases (Page 2 usually, but searching globally is safer for verification)
        PHASES=("New Moon" "Waxing Crescent" "First Quarter" "Waxing Gibbous" "Full Moon" "Waning Gibbous" "Third Quarter" "Waning Crescent")
        
        for phase in "${PHASES[@]}"; do
            if echo "$ALL_TEXT" | grep -qi "$phase"; then
                PHASE_COUNT=$((PHASE_COUNT + 1))
                FOUND_PHASES="$FOUND_PHASES, $phase"
            fi
        done

        # 2. Shape Analysis (Looking for circles/ellipses/shapes on Page 2 ideally)
        # We count total shapes across the document or specifically look for diagram elements
        # Patterns for shapes in ActivInspire XML: AsShape, AsCircle, AsEllipse, type="Circle", etc.
        SHAPE_COUNT=$(grep -rEc 'AsShape|AsCircle|AsEllipse|AsOval|type="Circle"|type="Ellipse"|shapeType="Circle"|shapeType="Ellipse"' "$TMP_DIR"/*.xml | awk -F: '{sum += $2} END {print sum+0}')
        
    fi
    rm -rf "$TMP_DIR"
fi

# Create result JSON
# Using python for safe JSON generation
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
    "has_duration": '$HAS_DURATION' == 'true',
    "has_sun": '$HAS_SUN' == 'true',
    "has_earth": '$HAS_EARTH' == 'true',
    "has_activity": '$HAS_ACTIVITY' == 'true',
    "has_order_term": '$HAS_ORDER_TERM' == 'true',
    "phase_count": $PHASE_COUNT,
    "found_phases": "$FOUND_PHASES",
    "shape_count": $SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Fallback if python fails
if [ ! -f /tmp/task_result.json ]; then
    echo '{"error": "Failed to generate JSON"}' > /tmp/task_result.json
fi

chmod 666 /tmp/task_result.json
echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="