#!/bin/bash
echo "=== Exporting Restaurant Menu Design Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
echo "Final screenshot saved"

# Target file paths
FILE_PATH="/home/ga/Documents/Flipcharts/restaurant_menu.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/restaurant_menu.flp"

# Initialize result variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
PAGE_COUNT=0
CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
LOGO_SHAPE_FOUND="false"

# Initialize text content flags
HAS_TITLE="false"
HAS_APPETIZERS_HEADER="false"
HAS_GARLIC="false"
HAS_MOZZ="false"
HAS_SALAD="false"
HAS_PRICE_450="false"
HAS_PRICE_600="false"
HAS_PRICE_525="false"

HAS_ENTREES_HEADER="false"
HAS_BURGER="false"
HAS_SALMON="false"
HAS_PASTA="false"
HAS_PRICE_1200="false"
HAS_PRICE_1850="false"
HAS_PRICE_1400="false"

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

    # Check creation time
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
        # We cat all xml files into one variable for easier grep
        ALL_XML_CONTENT=""
        for XML in "$TMP_DIR"/*.xml; do
            if [ -f "$XML" ]; then
                ALL_XML_CONTENT="$ALL_XML_CONTENT $(cat "$XML")"
            fi
        done

        # --- Text Verification ---
        # Branding
        if echo "$ALL_XML_CONTENT" | grep -qi "Golden Fork"; then HAS_TITLE="true"; fi

        # Appetizers Page
        if echo "$ALL_XML_CONTENT" | grep -qi "Appetizer"; then HAS_APPETIZERS_HEADER="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Garlic Bread"; then HAS_GARLIC="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Mozzarella"; then HAS_MOZZ="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Garden Salad"; then HAS_SALAD="true"; fi
        # Prices (match 4.50 or 4.5)
        if echo "$ALL_XML_CONTENT" | grep -q "4.50"; then HAS_PRICE_450="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -q "6.00"; then HAS_PRICE_600="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -q "5.25"; then HAS_PRICE_525="true"; fi

        # Entrees Page
        if echo "$ALL_XML_CONTENT" | grep -qi "Entree"; then HAS_ENTREES_HEADER="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Cheeseburger"; then HAS_BURGER="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Salmon"; then HAS_SALMON="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -qi "Pasta"; then HAS_PASTA="true"; fi
        # Prices
        if echo "$ALL_XML_CONTENT" | grep -q "12.00"; then HAS_PRICE_1200="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -q "18.50"; then HAS_PRICE_1850="true"; fi
        if echo "$ALL_XML_CONTENT" | grep -q "14.00"; then HAS_PRICE_1400="true"; fi

        # --- Shape Verification for Logo ---
        # Look for shape definitions in the XML.
        # "AsShape", "AsRectangle", "AsCircle", "AsStar", etc.
        # We look for something that isn't just a text box or container.
        # Often Text is also a shape, so we look for specific shape types or a count > text count.
        # A simple heuristic: check for common shape tags.
        if echo "$ALL_XML_CONTENT" | grep -qiE 'AsRectangle|AsCircle|AsEllipse|AsPolygon|AsStar|AsShape'; then
            LOGO_SHAPE_FOUND="true"
        fi

    fi
    rm -rf "$TMP_DIR"
fi

# Create JSON result using Python
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_valid": $FILE_VALID,
    "page_count": $PAGE_COUNT,
    "created_during_task": $CREATED_DURING_TASK,
    "logo_shape_found": $LOGO_SHAPE_FOUND,
    "content": {
        "has_title": $HAS_TITLE,
        "appetizers": {
            "header": $HAS_APPETIZERS_HEADER,
            "items": [$HAS_GARLIC, $HAS_MOZZ, $HAS_SALAD],
            "prices": [$HAS_PRICE_450, $HAS_PRICE_600, $HAS_PRICE_525]
        },
        "entrees": {
            "header": $HAS_ENTREES_HEADER,
            "items": [$HAS_BURGER, $HAS_SALMON, $HAS_PASTA],
            "prices": [$HAS_PRICE_1200, $HAS_PRICE_1850, $HAS_PRICE_1400]
        }
    },
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="