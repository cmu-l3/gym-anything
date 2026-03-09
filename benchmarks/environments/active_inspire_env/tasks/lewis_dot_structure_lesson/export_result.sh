#!/bin/bash
# Export script for Lewis Dot Structure Lesson task
# Analyzes the created flipchart file for content verification

echo "=== Exporting Lewis Dot Structure Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/lewis_dot_structures.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/lewis_dot_structures.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0

# Content flags
HAS_TITLE_TERMS="false"     # Lewis, Dot
HAS_OCTET="false"
HAS_COVALENT="false"
HAS_VALENCE_HEADER="false"
HAS_ELEMENTS="false"        # H, C, N, O
HAS_WATER_EX="false"        # H2O, Water
HAS_PRACTICE="false"        # Practice header
HAS_MOLECULES="false"       # CO2, NH3, CH4
SHAPE_COUNT=0

# Check if file exists
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
       [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Get page count
    PAGE_COUNT=$(get_flipchart_page_count "$ACTUAL_PATH")

    # content analysis
    TMP_DIR=$(mktemp -d)
    if unzip -q "$ACTUAL_PATH" -d "$TMP_DIR" 2>/dev/null; then
        
        # Concatenate all XML text for searching
        ALL_TEXT=""
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Only read text-like files
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done
        
        # Verify text requirements
        if echo "$ALL_TEXT" | grep -qi "Lewis" && echo "$ALL_TEXT" | grep -qi "Dot"; then
            HAS_TITLE_TERMS="true"
        fi
        
        if echo "$ALL_TEXT" | grep -qi "Octet"; then
            HAS_OCTET="true"
        fi

        if echo "$ALL_TEXT" | grep -qi "Covalent"; then
            HAS_COVALENT="true"
        fi

        if echo "$ALL_TEXT" | grep -qi "Valence" || echo "$ALL_TEXT" | grep -qi "Electron"; then
            HAS_VALENCE_HEADER="true"
        fi

        # Check for element symbols (requires careful matching to avoid partial words)
        # We look for explicit text objects or bounded text
        ELEM_MATCHES=0
        if echo "$ALL_TEXT" | grep -q ">H<\|>C<\|>N<\|>O<\| H \| C \| N \| O "; then
             HAS_ELEMENTS="true"
        fi

        if echo "$ALL_TEXT" | grep -qi "H2O\|Water"; then
            HAS_WATER_EX="true"
        fi

        if echo "$ALL_TEXT" | grep -qi "Practice"; then
            HAS_PRACTICE="true"
        fi

        if echo "$ALL_TEXT" | grep -qi "CO2" && \
           echo "$ALL_TEXT" | grep -qi "NH3" && \
           echo "$ALL_TEXT" | grep -qi "CH4"; then
            HAS_MOLECULES="true"
        fi

        # Count shapes (dots/circles/ellipses)
        # Search for shape definition tags in the XML
        # Common ActivInspire tags: AsShape, AsCircle, AsEllipse, AsRectangle (if used for dots)
        SHAPE_COUNT=$(grep -rcE 'AsShape|AsCircle|AsEllipse|AsOval|shapeType="Circle"|shapeType="Ellipse"' "$TMP_DIR"/*.xml 2>/dev/null | awk -F: '{sum += $2} END {print sum+0}')
        
    fi
    rm -rf "$TMP_DIR"
fi

# Create Python script to safely dump JSON
cat << PYEOF > /tmp/dump_result.py
import json

data = {
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "has_title_terms": $HAS_TITLE_TERMS,
    "has_octet": $HAS_OCTET,
    "has_covalent": $HAS_COVALENT,
    "has_valence_header": $HAS_VALENCE_HEADER,
    "has_elements": $HAS_ELEMENTS,
    "has_water_ex": $HAS_WATER_EX,
    "has_practice": $HAS_PRACTICE,
    "has_molecules": $HAS_MOLECULES,
    "shape_count": $SHAPE_COUNT,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

python3 /tmp/dump_result.py

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="