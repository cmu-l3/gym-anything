#!/bin/bash
# Export script for Probability Tree Diagram task

echo "=== Exporting Probability Tree Diagram Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/probability_tree_diagram.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/probability_tree_diagram.flp"

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
HAS_TERMS="false" # "Tree Diagram", "Outcome"
HAS_COIN_LABELS="false" # "Heads", "Tails"
HAS_OUTCOMES="false" # HH, HT, TH, TT
HAS_PROBS="false" # 1/2, 1/4
HAS_PRACTICE="false" # "Practice"

# Structure flags
LINE_COUNT=0
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

    # Check if file was created/modified during task
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Validate format and count pages
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
        PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")
    fi

    # Extract content for analysis
    # Flipchart files are ZIPs containing XML
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Consolidate all text content from XML files
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Only read text-like files
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE")"
            fi
        done

        # --- Text Analysis ---
        # Title
        if echo "$ALL_TEXT" | grep -qi "Compound Probability"; then
            HAS_TITLE="true"
        fi
        
        # Terms (Need at least 2 of 3)
        TERM_COUNT=0
        echo "$ALL_TEXT" | grep -qi "Tree Diagram" && TERM_COUNT=$((TERM_COUNT+1))
        echo "$ALL_TEXT" | grep -qi "Outcome" && TERM_COUNT=$((TERM_COUNT+1))
        echo "$ALL_TEXT" | grep -qi "Probability" && TERM_COUNT=$((TERM_COUNT+1))
        if [ "$TERM_COUNT" -ge 2 ]; then
            HAS_TERMS="true"
        fi

        # Coin Labels
        if echo "$ALL_TEXT" | grep -qi "Heads" && echo "$ALL_TEXT" | grep -qi "Tails"; then
            HAS_COIN_LABELS="true"
        fi

        # Outcomes (Need at least 3 of 4: HH, HT, TH, TT)
        OUTCOME_COUNT=0
        echo "$ALL_TEXT" | grep -q "HH" && OUTCOME_COUNT=$((OUTCOME_COUNT+1))
        echo "$ALL_TEXT" | grep -q "HT" && OUTCOME_COUNT=$((OUTCOME_COUNT+1))
        echo "$ALL_TEXT" | grep -q "TH" && OUTCOME_COUNT=$((OUTCOME_COUNT+1))
        echo "$ALL_TEXT" | grep -q "TT" && OUTCOME_COUNT=$((OUTCOME_COUNT+1))
        if [ "$OUTCOME_COUNT" -ge 3 ]; then
            HAS_OUTCOMES="true"
        fi

        # Probabilities
        if (echo "$ALL_TEXT" | grep -q "1/2" || echo "$ALL_TEXT" | grep -q "0.5") && \
           (echo "$ALL_TEXT" | grep -q "1/4" || echo "$ALL_TEXT" | grep -q "0.25"); then
            HAS_PROBS="true"
        fi

        # Practice Section
        if echo "$ALL_TEXT" | grep -qi "Practice" && echo "$ALL_TEXT" | grep -q "?"; then
            HAS_PRACTICE="true"
        fi

        # --- Structure Analysis (Lines/Shapes) ---
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text"; then
                # Count Line elements (AsLine, Connector, or shapes acting as lines)
                L=$(grep -ic 'AsLine\|type="Line"\|connector' "$XML_FILE" 2>/dev/null || echo 0)
                LINE_COUNT=$((LINE_COUNT + L))
                
                # Count generic shapes as fallback or additional info
                S=$(grep -ic 'AsShape\|AsRectangle\|AsCircle' "$XML_FILE" 2>/dev/null || echo 0)
                SHAPE_COUNT=$((SHAPE_COUNT + S))
            fi
        done

    fi
    rm -rf "$TMP_DIR"
fi

# Generate JSON Result using Python for safe formatting
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
    "has_terms": '$HAS_TERMS' == 'true',
    "has_coin_labels": '$HAS_COIN_LABELS' == 'true',
    "has_outcomes": '$HAS_OUTCOMES' == 'true',
    "has_probs": '$HAS_PROBS' == 'true',
    "has_practice": '$HAS_PRACTICE' == 'true',
    "line_count": $LINE_COUNT,
    "shape_count": $SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="