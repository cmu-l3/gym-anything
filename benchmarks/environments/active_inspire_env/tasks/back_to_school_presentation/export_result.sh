#!/bin/bash
# Export script for Back-to-School Presentation task

echo "=== Exporting Back-to-School Presentation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/back_to_school_night.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/back_to_school_night.flp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Initialize verification vars
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0
SHAPE_COUNT=0

# Text detection flags
FOUND_ENGLISH_10="false"
FOUND_RIVERA="false"
FOUND_ROOM_214="false"
FOUND_GRADING="false"
FOUND_CATEGORIES_COUNT=0
FOUND_PERCENTAGES_COUNT=0
FOUND_EMAIL="false"
FOUND_DATES_COUNT=0

if [ -f "$FILE_PATH" ]; then
    ACTUAL_PATH="$FILE_PATH"
    FILE_FOUND="true"
elif [ -f "$FILE_PATH_ALT" ]; then
    ACTUAL_PATH="$FILE_PATH_ALT"
    FILE_FOUND="true"
fi

if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")

    # Check validity and timestamp
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Concatenate all XML content for searching
        # Note: In some versions, text might be split, but grep usually finds it
        ALL_XML=$(find "$TMP_DIR" -name "*.xml" -print0 | xargs -0 cat)

        # Page 1 Checks
        if echo "$ALL_XML" | grep -qi "English 10"; then FOUND_ENGLISH_10="true"; fi
        if echo "$ALL_XML" | grep -qi "Rivera"; then FOUND_RIVERA="true"; fi
        if echo "$ALL_XML" | grep -qi "214"; then FOUND_ROOM_214="true"; fi

        # Page 2 Checks
        if echo "$ALL_XML" | grep -qi "Grading"; then FOUND_GRADING="true"; fi
        
        # Count Categories
        for cat in "Essays" "Participation" "Quizzes" "Projects" "Homework"; do
            if echo "$ALL_XML" | grep -qi "$cat"; then
                FOUND_CATEGORIES_COUNT=$((FOUND_CATEGORIES_COUNT + 1))
            fi
        done

        # Count Percentages (escape % for grep if needed, usually % works fine)
        for pct in "30%" "15%" "25%"; do
            if echo "$ALL_XML" | grep -Fq "$pct"; then
                FOUND_PERCENTAGES_COUNT=$((FOUND_PERCENTAGES_COUNT + 1))
            fi
        done
        # Note: 15% appears twice in requirements, grep count might be tricky if we don't count occurrences.
        # But simply finding the strings "30%", "15%", "25%" covers the requirement of usage.

        # Page 3 Checks
        if echo "$ALL_XML" | grep -qi "rivera@lincolnhs.edu"; then FOUND_EMAIL="true"; fi
        
        # Dates
        for d in "September 15" "October 20" "December 18"; do
            if echo "$ALL_XML" | grep -qi "$d"; then
                FOUND_DATES_COUNT=$((FOUND_DATES_COUNT + 1))
            fi
        done

        # Shape Count
        # Look for shape definitions in XML
        # AsRectangle, AsCircle, AsShape with type attributes
        SHAPE_COUNT=$(echo "$ALL_XML" | grep -oiE 'AsRectangle|AsShape|type="Rectangle"|shapeType="Rectangle"' | wc -l)
        
    fi
    rm -rf "$TMP_DIR"
fi

# Generate JSON result
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "shape_count": $SHAPE_COUNT,
    "content": {
        "english_10": $FOUND_ENGLISH_10,
        "rivera": $FOUND_RIVERA,
        "room_214": $FOUND_ROOM_214,
        "grading": $FOUND_GRADING,
        "categories_count": $FOUND_CATEGORIES_COUNT,
        "percentages_count": $FOUND_PERCENTAGES_COUNT,
        "email": $FOUND_EMAIL,
        "dates_count": $FOUND_DATES_COUNT
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="