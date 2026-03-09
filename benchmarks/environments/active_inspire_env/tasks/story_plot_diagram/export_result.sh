#!/bin/bash
# Export script for Story Plot Diagram task
set -e

echo "=== Exporting Story Plot Diagram Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Locate the Output File
EXPECTED_FILE="/home/ga/Documents/Flipcharts/plot_diagram_dangerous_game.flipchart"
EXPECTED_FILE_ALT="/home/ga/Documents/Flipcharts/plot_diagram_dangerous_game.flp"
FILE_FOUND="false"
FILE_PATH=""

if [ -f "$EXPECTED_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE"
elif [ -f "$EXPECTED_FILE_ALT" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE_ALT"
fi

# 4. Analyze File Content
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_DURING_TASK="false"
PAGE_COUNT=0
SHAPE_COUNT=0

# Text content flags
HAS_TITLE="false"
HAS_AUTHOR="false"
HAS_EXPOSITION="false"
HAS_RISING="false"
HAS_CLIMAX="false"
HAS_FALLING="false"
HAS_RESOLUTION="false"
HAS_RAINSFORD="false"
HAS_ZAROFF="false"
HAS_DISCUSSION="false"

if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")

    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Create temp dir for extraction
    TEMP_DIR=$(mktemp -d)
    
    # Try to unzip (Flipcharts are ZIPs of XMLs)
    if unzip -q "$FILE_PATH" -d "$TEMP_DIR" 2>/dev/null; then
        
        # Count pages (usually represented by page*.xml files or structure in content.xml)
        # ActivInspire often uses a folder structure or page N.xml files
        PAGE_XMLS=$(find "$TEMP_DIR" -name "page*.xml" 2>/dev/null | wc -l)
        if [ "$PAGE_XMLS" -eq 0 ]; then
            # Fallback: count page tags in the main content.xml if monolithic
            PAGE_COUNT=$(grep -c "<page " "$TEMP_DIR/content.xml" 2>/dev/null || echo "0")
        else
            PAGE_COUNT=$PAGE_XMLS
        fi

        # Concatenate all XML content for text searching
        ALL_TEXT=$(grep -r "" "$TEMP_DIR" 2>/dev/null || true)

        # Check for required text terms (case insensitive)
        echo "$ALL_TEXT" | grep -qi "Most Dangerous Game" && HAS_TITLE="true"
        echo "$ALL_TEXT" | grep -qi "Connell" && HAS_AUTHOR="true"
        echo "$ALL_TEXT" | grep -qi "Exposition" && HAS_EXPOSITION="true"
        echo "$ALL_TEXT" | grep -qi "Rising Action" && HAS_RISING="true"
        echo "$ALL_TEXT" | grep -qi "Climax" && HAS_CLIMAX="true"
        echo "$ALL_TEXT" | grep -qi "Falling Action" && HAS_FALLING="true"
        echo "$ALL_TEXT" | grep -qi "Resolution" && HAS_RESOLUTION="true"
        echo "$ALL_TEXT" | grep -qi "Rainsford" && HAS_RAINSFORD="true"
        echo "$ALL_TEXT" | grep -qi "Zaroff" && HAS_ZAROFF="true"
        echo "$ALL_TEXT" | grep -qi "Discussion" && HAS_DISCUSSION="true"

        # Count Shapes
        # Look for ActivInspire shape elements (AsShape, AsRectangle, AsLine, etc.)
        # We look for 'type=' attributes often associated with shapes or the AsShape tag
        SHAPE_MATCHES=$(grep -rE "<AsShape|<AsRectangle|<AsLine|<AsTriangle|<AsPolygon" "$TEMP_DIR" | wc -l)
        SHAPE_COUNT=$SHAPE_MATCHES
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
fi

# 5. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "file_found": $FILE_FOUND,
    "file_path": "$FILE_PATH",
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "shape_count": $SHAPE_COUNT,
    "text_content": {
        "has_title": $HAS_TITLE,
        "has_author": $HAS_AUTHOR,
        "has_exposition": $HAS_EXPOSITION,
        "has_rising": $HAS_RISING,
        "has_climax": $HAS_CLIMAX,
        "has_falling": $HAS_FALLING,
        "has_resolution": $HAS_RESOLUTION,
        "has_rainsford": $HAS_RAINSFORD,
        "has_zaroff": $HAS_ZAROFF,
        "has_discussion": $HAS_DISCUSSION
    },
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json