#!/bin/bash
# Export script for Coordinate Plane Activity
# Analyzes the created flipchart for content and structure

echo "=== Exporting Coordinate Plane Activity Result ==="

source /workspace/scripts/task_utils.sh

# Record paths
TARGET_FILE="/home/ga/Documents/Flipcharts/coordinate_plane.flipchart"
TARGET_FILE_ALT="/home/ga/Documents/Flipcharts/coordinate_plane.flp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Initialize result variables
FILE_FOUND="false"
FILE_PATH=""
FILE_VALID="false"
CREATED_DURING_TASK="false"
PAGE_COUNT=0
SHAPE_COUNT=0

# Text detection flags
HAS_TITLE="false"
HAS_INSTRUCTION="false"
HAS_X_AXIS="false"
HAS_Y_AXIS="false"
HAS_QUADRANTS=0  # Count of I, II, III, IV found
HAS_POINTS=0     # Count of specific coordinates found
POINTS_DETAILS=""

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Check if file exists
if [ -f "$TARGET_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$TARGET_FILE"
elif [ -f "$TARGET_FILE_ALT" ]; then
    FILE_FOUND="true"
    FILE_PATH="$TARGET_FILE_ALT"
fi

if [ "$FILE_FOUND" = "true" ]; then
    echo "File found at: $FILE_PATH"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Validate file format (ZIP containing XML)
    if check_flipchart_file "$FILE_PATH" | grep -q "valid"; then
        FILE_VALID="true"
        
        # Extract metadata
        PAGE_COUNT=$(get_flipchart_page_count "$FILE_PATH")
        
        # Create temp dir for content analysis
        TMP_DIR=$(mktemp -d)
        if unzip -q "$FILE_PATH" -d "$TMP_DIR" 2>/dev/null; then
            
            # Concatenate all XML content for searching
            ALL_XML=$(find "$TMP_DIR" -name "*.xml" -exec cat {} \;)
            
            # 1. Check Title and Instructions
            if echo "$ALL_XML" | grep -qi "Plotting Ordered Pairs"; then
                HAS_TITLE="true"
            fi
            if echo "$ALL_XML" | grep -qi "coordinate plane"; then
                HAS_INSTRUCTION="true"
            fi
            
            # 2. Check Axes Labels (Case sensitive for single letters usually, but XML might hide it)
            # We look for >x< or "x" patterns often found in text objects
            if echo "$ALL_XML" | grep -qE ">x<| x |\"x\""; then
                HAS_X_AXIS="true"
            fi
            if echo "$ALL_XML" | grep -qE ">y<| y |\"y\""; then
                HAS_Y_AXIS="true"
            fi
            
            # 3. Check Quadrant Labels (I, II, III, IV)
            # Using grep count for specific roman numerals
            Q_COUNT=0
            echo "$ALL_XML" | grep -qE ">I<| I |\"I\"" && ((Q_COUNT++))
            echo "$ALL_XML" | grep -qE ">II<| II |\"II\"" && ((Q_COUNT++))
            echo "$ALL_XML" | grep -qE ">III<| III |\"III\"" && ((Q_COUNT++))
            echo "$ALL_XML" | grep -qE ">IV<| IV |\"IV\"" && ((Q_COUNT++))
            HAS_QUADRANTS=$Q_COUNT
            
            # 4. Check Specific Points
            # We search for the specific strings "(3, 4)", etc.
            # Spaces might vary, so we remove spaces from XML content for this specific check
            CLEAN_XML=$(echo "$ALL_XML" | tr -d ' ')
            
            P_COUNT=0
            DETAILS="Found: "
            
            if echo "$CLEAN_XML" | grep -Fq "(3,4)"; then ((P_COUNT++)); DETAILS+="(3,4) "; fi
            if echo "$CLEAN_XML" | grep -Fq "(-2,5)"; then ((P_COUNT++)); DETAILS+="(-2,5) "; fi
            if echo "$CLEAN_XML" | grep -Fq "(-4,-3)"; then ((P_COUNT++)); DETAILS+="(-4,-3) "; fi
            if echo "$CLEAN_XML" | grep -Fq "(5,-2)"; then ((P_COUNT++)); DETAILS+="(5,-2) "; fi
            if echo "$CLEAN_XML" | grep -Fq "(0,0)"; then ((P_COUNT++)); DETAILS+="(0,0) "; fi
            
            HAS_POINTS=$P_COUNT
            POINTS_DETAILS=$DETAILS
            
            # 5. Count Shapes
            # Look for AsShape, AsLine, AsCircle, etc.
            # Lines for axes (2) + Points (5) = min 7 shapes expected
            SHAPE_COUNT=$(echo "$ALL_XML" | grep -cE "AsShape|AsLine|AsCircle|AsEllipse|AsRectangle|type=\"Shape\"")
            
        fi
        rm -rf "$TMP_DIR"
    fi
fi

# Create result JSON safely using Python
python3 << PYEOF
import json
import os

result = {
    "file_found": $FILE_FOUND,
    "file_valid": $FILE_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "page_count": $PAGE_COUNT,
    "has_title": $HAS_TITLE,
    "has_instruction": $HAS_INSTRUCTION,
    "has_x_axis": $HAS_X_AXIS,
    "has_y_axis": $HAS_Y_AXIS,
    "quadrants_count": $HAS_QUADRANTS,
    "points_count": $HAS_POINTS,
    "points_details": "$POINTS_DETAILS",
    "shape_count": $SHAPE_COUNT,
    "screenshot_path": "/tmp/task_final_state.png"
}

# Write to temp file first then move
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

os.chmod('/tmp/task_result_temp.json', 0o666)
PYEOF

mv /tmp/task_result_temp.json /tmp/task_result.json

echo "Analysis complete. Result:"
cat /tmp/task_result.json