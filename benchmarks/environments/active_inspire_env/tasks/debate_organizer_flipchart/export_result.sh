#!/bin/bash
# Export script for Debate Organizer Flipchart task

echo "=== Exporting Debate Organizer Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/cell_phone_debate.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/cell_phone_debate.flp"

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
HAS_TITLE="false"      # Socratic Seminar
HAS_TOPIC="false"      # Cell phones
HAS_RULES="false"      # Rules keywords
HAS_PRO="false"
HAS_CON="false"
HAS_ARGS="false"       # Argument keywords
HAS_STARTERS="false"   # Sentence starter keywords
HAS_LINES="false"      # T-chart lines/shapes

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
    if check_flipchart_file "$ACTUAL_PATH"; then
        FILE_VALID="true"
    fi

    # Check anti-gaming timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Extract content for analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate text from all XMLs for easier searching
        # Note: In a real robust checker, we might check page-by-page, 
        # but global existence is usually sufficient for this level.
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Only read text files
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Check for Title
        if echo "$ALL_TEXT" | grep -qi "Socratic Seminar"; then
            HAS_TITLE="true"
        fi

        # Check for Topic
        if echo "$ALL_TEXT" | grep -qi "cell phone"; then
            HAS_TOPIC="true"
        fi

        # Check for Rules (flexible matching)
        RULES_MATCHES=0
        if echo "$ALL_TEXT" | grep -qi "respect"; then ((RULES_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "evidence"; then ((RULES_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "build"; then ((RULES_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "speak"; then ((RULES_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "listen"; then ((RULES_MATCHES++)); fi
        if [ "$RULES_MATCHES" -ge 1 ]; then HAS_RULES="true"; fi

        # Check for T-Chart labels
        if echo "$ALL_TEXT" | grep -q "Pro" && echo "$ALL_TEXT" | grep -q "Con"; then
            HAS_PRO="true"
            HAS_CON="true"
        fi

        # Check for Arguments (flexible matching of examples)
        ARG_MATCHES=0
        if echo "$ALL_TEXT" | grep -qi "app\|education\|learn"; then ((ARG_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "distract\|bully\|cheat"; then ((ARG_MATCHES++)); fi
        if [ "$ARG_MATCHES" -ge 1 ]; then HAS_ARGS="true"; fi

        # Check for Sentence Starters
        STARTER_MATCHES=0
        if echo "$ALL_TEXT" | grep -qi "believe\|think"; then ((STARTER_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "disagree\|agree"; then ((STARTER_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "because"; then ((STARTER_MATCHES++)); fi
        if echo "$ALL_TEXT" | grep -qi "evidence\|example"; then ((STARTER_MATCHES++)); fi
        if [ "$STARTER_MATCHES" -ge 2 ]; then HAS_STARTERS="true"; fi

        # Check for Shapes (Lines/Rectangles for T-Chart)
        # Looking for line or rectangle elements in XML
        SHAPE_COUNT=0
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                # Count lines and rectangles
                L=$(grep -ic 'AsLine\|type="Line"\|shapeType="Line"' "$XML_FILE" 2>/dev/null || echo 0)
                R=$(grep -ic 'AsRectangle\|type="Rectangle"' "$XML_FILE" 2>/dev/null || echo 0)
                SHAPE_COUNT=$((SHAPE_COUNT + L + R))
            fi
        done
        
        if [ "$SHAPE_COUNT" -ge 2 ]; then
            HAS_LINES="true"
        fi

    fi
    rm -rf "$TMP_DIR"
fi

# Write result to JSON
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
    "has_topic": '$HAS_TOPIC' == 'true',
    "has_rules": '$HAS_RULES' == 'true',
    "has_pro": '$HAS_PRO' == 'true',
    "has_con": '$HAS_CON' == 'true',
    "has_args": '$HAS_ARGS' == 'true',
    "has_starters": '$HAS_STARTERS' == 'true',
    "has_lines": '$HAS_LINES' == 'true',
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="