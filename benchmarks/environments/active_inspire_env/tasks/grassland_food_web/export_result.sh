#!/bin/bash
# Export script for Grassland Food Web task
# Analyzes the flipchart structure (XML inside ZIP) to verify content

echo "=== Exporting Grassland Food Web Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/grassland_food_web.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/grassland_food_web.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Initialize Result Variables
FILE_FOUND="false"
ACTUAL_PATH=""
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0

# Page Content Flags
HAS_TITLE="false"           # Page 1
HAS_TERMS="false"           # Page 1 (Producer/Consumer/Decomposer)
HAS_GRASS="false"           # Page 2
HAS_GRASSHOPPER="false"     # Page 2
HAS_FROG="false"            # Page 2
HAS_SNAKE_HAWK="false"      # Page 2
HAS_FUNGI="false"           # Page 2
ARROW_COUNT=0               # Page 2
HAS_PYRAMID_TITLE="false"   # Page 3
PYRAMID_SHAPE_COUNT=0       # Page 3
HAS_PYRAMID_LABELS="false"  # Page 3

# Check for file existence
if [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    FILE_FOUND="true"
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

if [ "$FILE_FOUND" = "true" ]; then
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$ACTUAL_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check validity (ActivInspire files are ZIPs)
    if unzip -t "$ACTUAL_PATH" >/dev/null 2>&1; then
        FILE_VALID="true"
    fi
    
    # Analyze Content
    # We extract to a temp dir to parse the XML pages
    TEMP_DIR=$(mktemp -d)
    unzip -q "$ACTUAL_PATH" -d "$TEMP_DIR" 2>/dev/null
    
    # Count Pages (look for page*.xml files or directories)
    # ActivInspire format varies, usually separate XMLs for pages
    PAGE_COUNT=$(find "$TEMP_DIR" -name "page*.xml" 2>/dev/null | wc -l)
    if [ "$PAGE_COUNT" -eq 0 ]; then
        # Alternative structure: folders named page 1, page 2...
        PAGE_COUNT=$(find "$TEMP_DIR" -type d -name "page*" 2>/dev/null | wc -l)
    fi
    # Fallback: if single file structure, count <page> tags
    if [ "$PAGE_COUNT" -eq 0 ]; then
         PAGE_COUNT=$(grep -c "<page" "$TEMP_DIR"/*.xml 2>/dev/null || echo 0)
    fi

    # IDENTIFY PAGES BY CONTENT
    # Since we can't guarantee page order, we look for key terms to identify which XML file corresponds to which page task
    
    # 1. Search for Page 1 (Intro) candidates
    # Look for file containing "Grassland" or "Food Web"
    PAGE1_FILE=$(grep -l -i "Grassland\|Food Web" "$TEMP_DIR"/*.xml "$TEMP_DIR"/*/content.xml 2>/dev/null | head -1)
    
    if [ -n "$PAGE1_FILE" ]; then
        HAS_TITLE="true"
        CONTENT=$(cat "$PAGE1_FILE")
        # Check for terms
        if echo "$CONTENT" | grep -qi "Producer" && \
           echo "$CONTENT" | grep -qi "Consumer" && \
           echo "$CONTENT" | grep -qi "Decomposer"; then
            HAS_TERMS="true"
        fi
    fi

    # 2. Search for Page 2 (Food Web) candidates
    # Look for file containing specific organisms
    PAGE2_FILE=$(grep -l -i "Grasshopper\|Frog\|Snake" "$TEMP_DIR"/*.xml "$TEMP_DIR"/*/content.xml 2>/dev/null | head -1)
    
    if [ -n "$PAGE2_FILE" ]; then
        CONTENT=$(cat "$PAGE2_FILE")
        if echo "$CONTENT" | grep -qi "Grass[^h]"; then HAS_GRASS="true"; fi # Grass but not Grasshopper
        if echo "$CONTENT" | grep -qi "Grasshopper"; then HAS_GRASSHOPPER="true"; fi
        if echo "$CONTENT" | grep -qi "Frog"; then HAS_FROG="true"; fi
        if echo "$CONTENT" | grep -qi "Snake" && echo "$CONTENT" | grep -qi "Hawk"; then HAS_SNAKE_HAWK="true"; fi
        if echo "$CONTENT" | grep -qi "Fungi\|Decomposer"; then HAS_FUNGI="true"; fi
        
        # Count Arrows/Lines on this page
        # Look for AsLine, AsArrow, AsConnector, or shapes with startArrow/endArrow attributes
        # Common ActivInspire tags for lines: <AsLine>, <AsConnector>
        ARROW_COUNT=$(grep -ciE "AsLine|AsConnector|AsArrow|endArrow|startArrow" "$PAGE2_FILE")
    fi

    # 3. Search for Page 3 (Pyramid) candidates
    # Look for file containing "Pyramid"
    PAGE3_FILE=$(grep -l -i "Pyramid" "$TEMP_DIR"/*.xml "$TEMP_DIR"/*/content.xml 2>/dev/null | head -1)
    
    if [ -n "$PAGE3_FILE" ]; then
        HAS_PYRAMID_TITLE="true"
        CONTENT=$(cat "$PAGE3_FILE")
        
        # Check labels
        if echo "$CONTENT" | grep -qi "Primary" && \
           echo "$CONTENT" | grep -qi "Secondary"; then
            HAS_PYRAMID_LABELS="true"
        fi
        
        # Count Shapes (Pyramid layers)
        # Look for rectangles, triangles, or generic shapes
        # Exclude text boxes (AsText)
        # Count tags like <AsShape>, <AsRectangle>, <AsTriangle>, <AsPolygon>
        PYRAMID_SHAPE_COUNT=$(grep -ciE "AsShape|AsRectangle|AsTriangle|AsPolygon" "$PAGE3_FILE")
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
fi

# Create JSON Result
python3 << PYEOF
import json

result = {
    "file_found": $FILE_FOUND,
    "file_valid": '$FILE_VALID' == 'true',
    "created_during_task": '$CREATED_DURING_TASK' == 'true',
    "page_count": $PAGE_COUNT,
    "has_title": '$HAS_TITLE' == 'true',
    "has_terms": '$HAS_TERMS' == 'true',
    "has_grass": '$HAS_GRASS' == 'true',
    "has_grasshopper": '$HAS_GRASSHOPPER' == 'true',
    "has_frog": '$HAS_FROG' == 'true',
    "has_snake_hawk": '$HAS_SNAKE_HAWK' == 'true',
    "has_fungi": '$HAS_FUNGI' == 'true',
    "arrow_count": $ARROW_COUNT,
    "has_pyramid_title": '$HAS_PYRAMID_TITLE' == 'true',
    "pyramid_shape_count": $PYRAMID_SHAPE_COUNT,
    "has_pyramid_labels": '$HAS_PYRAMID_LABELS' == 'true',
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="