#!/bin/bash
echo "=== Exporting Artwork Annotation Analysis results ==="

source /workspace/scripts/task_utils.sh

# Record paths and times
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/Flipcharts/artwork_analysis.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/artwork_analysis.flp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if file exists
if [ -f "$FILE_PATH" ]; then
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    ACTUAL_PATH="$FILE_PATH_ALT"
else
    ACTUAL_PATH=""
fi

# Initialize results
FILE_EXISTS="false"
FILE_SIZE=0
IS_VALID_ZIP="false"
PAGE_COUNT=0
IMAGE_EMBEDDED="false"
ARROW_COUNT=0
FOUND_TERMS=""
CREATED_DURING_TASK="false"

if [ -n "$ACTUAL_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ACTUAL_PATH" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c %Y "$ACTUAL_PATH" 2>/dev/null || echo 0)

    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Create temp dir for analysis
    TEMP_DIR=$(mktemp -d)

    # Try to unzip (Flipcharts are ZIPs)
    if unzip -q -o "$ACTUAL_PATH" -d "$TEMP_DIR" 2>/dev/null; then
        IS_VALID_ZIP="true"

        # 1. Count Pages (count page*.xml files)
        PAGE_COUNT=$(find "$TEMP_DIR" -name "page*.xml" | wc -l)
        # Fallback: if structure is different, count <page> tags in main xml
        if [ "$PAGE_COUNT" -eq 0 ]; then
             PAGE_COUNT=$(grep -r "<page " "$TEMP_DIR" 2>/dev/null | wc -l)
        fi

        # 2. Check for Embedded Images
        # Look for image files inside the extracted archive
        IMG_COUNT=$(find "$TEMP_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" \) | wc -l)
        if [ "$IMG_COUNT" -gt 0 ]; then
            IMAGE_EMBEDDED="true"
        fi

        # 3. Text Analysis (Search all XMLs)
        ALL_TEXT=$(grep -rEi "text" "$TEMP_DIR" 2>/dev/null | tr -d '\n' | tr -d '\r')

        # Accumulate found terms for python verification
        # We search specifically for the required terms
        TERMS_TO_CHECK=("Great Wave" "Hokusai" "foreground" "background" "wave" "Elements of Art" "line" "color" "shape" "texture" "contrast" "movement")

        FOUND_LIST=""
        for term in "${TERMS_TO_CHECK[@]}"; do
            # Use grep -i for case insensitive search in all files
            if grep -rqi "$term" "$TEMP_DIR"; then
                FOUND_LIST="${FOUND_LIST}|${term}"
            fi
        done
        FOUND_TERMS="$FOUND_LIST"

        # 4. Shape/Arrow Analysis
        # Search for Line/Arrow shapes in XML
        # Common identifiers: type="Line", shapeType="Line", startCap="Arrow", endCap="Arrow"
        # Also AsConnector
        ARROW_MATCHES=$(grep -riE 'type="Line"|type="Arrow"|endCap="Arrow"|startCap="Arrow"|shapeType="Line"|AsConnector' "$TEMP_DIR" | wc -l)
        ARROW_COUNT=$ARROW_MATCHES

    fi
    rm -rf "$TEMP_DIR"
fi

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "is_valid_zip": $IS_VALID_ZIP,
    "page_count": $PAGE_COUNT,
    "image_embedded": $IMAGE_EMBEDDED,
    "found_terms_string": "$FOUND_TERMS",
    "arrow_count": $ARROW_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json