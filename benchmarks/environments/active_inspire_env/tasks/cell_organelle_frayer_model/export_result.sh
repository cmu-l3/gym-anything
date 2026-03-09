#!/bin/bash
echo "=== Exporting Cell Organelle Frayer Model Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/cell_organelle_frayer.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/cell_organelle_frayer.flp"

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
HAS_MITOCHONDRIA="false"
HAS_CELL_MEMBRANE="false"
HAS_DEFINITION="false"
HAS_CHARACTERISTICS="false"
HAS_EXAMPLES="false"
HAS_NON_EXAMPLES="false"

# Content keywords (Mitochondria)
HAS_ATP="false"
HAS_ENERGY="false"
HAS_RESPIRATION="false"

# Content keywords (Membrane)
HAS_BARRIER="false"
HAS_PERMEABLE="false"
HAS_PHOSPHOLIPID="false"

# Shape counts
RECT_COUNT=0
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

    # Check validity (zip/xml structure)
    if check_flipchart_file "$ACTUAL_PATH" | grep -q "valid"; then
        FILE_VALID="true"
    fi

    # Check timestamp
    if [ -n "$FILE_MTIME" ] && [ -n "$TASK_START" ] && \
       [ "$FILE_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # Analyze content
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Aggregate all text content
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Only read text/xml files
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done

        # Check for Main Terms
        if echo "$ALL_TEXT" | grep -qi "Mitochondria"; then HAS_MITOCHONDRIA="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Cell Membrane\|CellMembrane"; then HAS_CELL_MEMBRANE="true"; fi

        # Check for Quadrant Labels
        if echo "$ALL_TEXT" | grep -qi "Definition"; then HAS_DEFINITION="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Characteristic"; then HAS_CHARACTERISTICS="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Example"; then HAS_EXAMPLES="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Non-Example\|Non Example"; then HAS_NON_EXAMPLES="true"; fi

        # Check for Domain Content (Mitochondria)
        if echo "$ALL_TEXT" | grep -qi "ATP"; then HAS_ATP="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Energy"; then HAS_ENERGY="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Respiration"; then HAS_RESPIRATION="true"; fi

        # Check for Domain Content (Membrane)
        if echo "$ALL_TEXT" | grep -qi "Barrier"; then HAS_BARRIER="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Permeable"; then HAS_PERMEABLE="true"; fi
        if echo "$ALL_TEXT" | grep -qi "Phospholipid\|Lipid"; then HAS_PHOSPHOLIPID="true"; fi

        # Count Rectangles (AsRectangle, type="Rectangle")
        # We search across all XML files
        RECT_COUNT=$(grep -riE 'AsRectangle|type="Rectangle"|shapeType="Rectangle"' "$TMP_DIR" | wc -l)
        TOTAL_SHAPE_COUNT=$(grep -riE 'AsShape' "$TMP_DIR" | wc -l)
        
    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON Result
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
    "has_mitochondria": '$HAS_MITOCHONDRIA' == 'true',
    "has_cell_membrane": '$HAS_CELL_MEMBRANE' == 'true',
    "has_definition": '$HAS_DEFINITION' == 'true',
    "has_characteristics": '$HAS_CHARACTERISTICS' == 'true',
    "has_examples": '$HAS_EXAMPLES' == 'true',
    "has_non_examples": '$HAS_NON_EXAMPLES' == 'true',
    "has_atp": '$HAS_ATP' == 'true',
    "has_energy": '$HAS_ENERGY' == 'true',
    "has_respiration": '$HAS_RESPIRATION' == 'true',
    "has_barrier": '$HAS_BARRIER' == 'true',
    "has_permeable": '$HAS_PERMEABLE' == 'true',
    "has_phospholipid": '$HAS_PHOSPHOLIPID' == 'true',
    "rect_count": $RECT_COUNT,
    "total_shape_count": $TOTAL_SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written successfully")
PYEOF

chmod 666 /tmp/task_result.json
echo "=== Export Complete ==="