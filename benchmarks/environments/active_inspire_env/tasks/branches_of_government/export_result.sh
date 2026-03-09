#!/bin/bash
# Export script for Branches of Government task
echo "=== Exporting Branches of Government Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/branches_of_government.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/branches_of_government.flp"

# Initialize variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content analysis flags
HAS_TITLE="false"
HAS_LEGISLATIVE="false"
HAS_EXECUTIVE="false"
HAS_JUDICIAL="false"
HAS_CONGRESS="false"
HAS_SENATE="false"
HAS_HOUSE="false"
HAS_PRESIDENT="false"
HAS_SUPREME_COURT="false"
HAS_CHECKS_TITLE="false"
CHECK_EXAMPLES_COUNT=0

# Shape analysis
SHAPE_COUNT=0

# Check existence
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

    # Validate zip format
    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate text from all XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Only read text/xml files
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # --- Text Analysis ---
        # Normalize text for searching (could use tr for case, but grep -i handles it)
        
        # Overview terms
        if echo "$ALL_TEXT" | grep -qi "Three Branches\|Branches of Government"; then HAS_TITLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Legislative"; then HAS_LEGISLATIVE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Executive"; then HAS_EXECUTIVE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Judicial"; then HAS_JUDICIAL="true"; fi

        # Detail terms
        if echo "$ALL_TEXT" | grep -qi "Congress"; then HAS_CONGRESS="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Senate"; then HAS_SENATE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "House of Representatives\|House"; then HAS_HOUSE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "President"; then HAS_PRESIDENT="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Supreme Court"; then HAS_SUPREME_COURT="true"; fi

        # Checks and Balances
        if echo "$ALL_TEXT" | grep -qi "Checks" && echo "$ALL_TEXT" | grep -qi "Balances"; then
            HAS_CHECKS_TITLE="true"
        fi

        # Check examples count
        # Examples: veto, impeach, override, appoint, confirm, judicial review
        EXAMPLES_FOUND=0
        if echo "$ALL_TEXT" | grep -qi "veto"; then EXAMPLES_FOUND=$((EXAMPLES_FOUND+1)); fi
        if echo "$ALL_TEXT" | grep -qi "impeach"; then EXAMPLES_FOUND=$((EXAMPLES_FOUND+1)); fi
        if echo "$ALL_TEXT" | grep -qi "override"; then EXAMPLES_FOUND=$((EXAMPLES_FOUND+1)); fi
        if echo "$ALL_TEXT" | grep -qi "appoint"; then EXAMPLES_FOUND=$((EXAMPLES_FOUND+1)); fi
        if echo "$ALL_TEXT" | grep -qi "confirm"; then EXAMPLES_FOUND=$((EXAMPLES_FOUND+1)); fi
        if echo "$ALL_TEXT" | grep -qi "judicial review\|unconstitutional"; then EXAMPLES_FOUND=$((EXAMPLES_FOUND+1)); fi
        CHECK_EXAMPLES_COUNT=$EXAMPLES_FOUND

        # --- Shape Analysis ---
        # Count shape elements in XML
        # Looking for AsShape, AsRectangle, AsCircle, AsConnector, AsLine
        TOTAL_SHAPES=0
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Count occurrences of shape definitions
            S=$(grep -ic 'AsShape\|AsRectangle\|AsCircle\|AsEllipse\|AsConnector\|AsLine\|shapeType=' "$XML_FILE" 2>/dev/null || echo 0)
            TOTAL_SHAPES=$((TOTAL_SHAPES + S))
        done
        SHAPE_COUNT=$TOTAL_SHAPES
    fi
    rm -rf "$TMP_DIR"
fi

# Write JSON output
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "has_title": '$HAS_TITLE' == 'true',
    "branches_found": {
        "legislative": '$HAS_LEGISLATIVE' == 'true',
        "executive": '$HAS_EXECUTIVE' == 'true',
        "judicial": '$HAS_JUDICIAL' == 'true'
    },
    "details_found": {
        "congress": '$HAS_CONGRESS' == 'true',
        "senate": '$HAS_SENATE' == 'true',
        "house": '$HAS_HOUSE' == 'true',
        "president": '$HAS_PRESIDENT' == 'true',
        "supreme_court": '$HAS_SUPREME_COURT' == 'true'
    },
    "checks_title": '$HAS_CHECKS_TITLE' == 'true',
    "check_examples_count": $CHECK_EXAMPLES_COUNT,
    "shape_count": $SHAPE_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export Complete ==="