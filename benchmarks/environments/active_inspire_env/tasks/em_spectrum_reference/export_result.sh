#!/bin/bash
echo "=== Exporting EM Spectrum Reference Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/em_spectrum_reference.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/em_spectrum_reference.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Content tracking
FOUND_BANDS=()
FOUND_COLORS=()
FOUND_APPS=()
SHAPE_COUNT=0
HAS_TITLE="false"
HAS_NM="false"

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
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
            # Basic check to avoid binary files masquerading as XML
            if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII\|UTF"; then
                ALL_TEXT="$ALL_TEXT $(cat "$XML_FILE" 2>/dev/null)"
            fi
        done
        
        # Normalize text for searching
        SEARCH_TEXT=$(echo "$ALL_TEXT" | tr '[:upper:]' '[:lower:]')

        # Check Title
        if echo "$SEARCH_TEXT" | grep -q "electromagnetic spectrum"; then
            HAS_TITLE="true"
        fi

        # Check Wavelength unit
        if echo "$SEARCH_TEXT" | grep -q "nm"; then
            HAS_NM="true"
        fi

        # Check Bands (Radio, Microwave, Infrared, Visible, Ultraviolet, X-ray, Gamma)
        BANDS=("radio" "microwave" "infrared" "visible" "ultraviolet" "x-ray" "gamma")
        for band in "${BANDS[@]}"; do
            if echo "$SEARCH_TEXT" | grep -q "$band"; then
                FOUND_BANDS+=("$band")
            # Handle X-ray variation
            elif [ "$band" == "x-ray" ] && echo "$SEARCH_TEXT" | grep -q "xray"; then
                FOUND_BANDS+=("$band")
            fi
        done

        # Check Colors
        COLORS=("red" "orange" "yellow" "green" "blue" "indigo" "violet")
        for color in "${COLORS[@]}"; do
            if echo "$SEARCH_TEXT" | grep -q "$color"; then
                FOUND_COLORS+=("$color")
            fi
        done

        # Check Applications (keywords)
        APPS=("communication" "broadcasting" "cooking" "radar" "medical" "imaging" "cancer" "sterilization" "heating" "phone" "wifi")
        for app in "${APPS[@]}"; do
            if echo "$SEARCH_TEXT" | grep -q "$app"; then
                FOUND_APPS+=("$app")
            fi
        done

        # Count Shapes
        # ActivInspire shapes often appear as AsRectangle, AsShape, etc.
        # We count explicit rectangles and general shapes
        for XML_FILE in "$TMP_DIR"/*.xml; do
            [ -f "$XML_FILE" ] || continue
             if file "$XML_FILE" 2>/dev/null | grep -qi "xml\|text\|ASCII"; then
                # Count occurrences of shape definitions
                S=$(grep -ic 'AsRectangle\|shapeType="Rectangle"\|type="Rectangle"\|AsShape' "$XML_FILE" 2>/dev/null || echo 0)
                SHAPE_COUNT=$((SHAPE_COUNT + S))
            fi
        done
    fi
    rm -rf "$TMP_DIR"
fi

# Join arrays for JSON
JOINED_BANDS=$(printf "\"%s\"," "${FOUND_BANDS[@]}" | sed 's/,$//')
JOINED_COLORS=$(printf "\"%s\"," "${FOUND_COLORS[@]}" | sed 's/,$//')
JOINED_APPS=$(printf "\"%s\"," "${FOUND_APPS[@]}" | sed 's/,$//')

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_found": $FILE_FOUND,
    "file_path": "$ACTUAL_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "has_title": $HAS_TITLE,
    "has_nm_unit": $HAS_NM,
    "found_bands": [$JOINED_BANDS],
    "found_colors": [$JOINED_COLORS],
    "found_apps": [$JOINED_APPS],
    "shape_count": $SHAPE_COUNT,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="