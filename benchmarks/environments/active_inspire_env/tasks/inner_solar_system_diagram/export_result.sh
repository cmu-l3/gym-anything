#!/bin/bash
echo "=== Exporting Inner Solar System Diagram Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Define expected paths
EXPECTED_FILE="/home/ga/Documents/Flipcharts/inner_solar_system.flipchart"
EXPECTED_FILE_ALT="/home/ga/Documents/Flipcharts/inner_solar_system.flp"

# Initialize result variables
FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"

# Content analysis variables
HAS_SUN_LABEL="false"
HAS_PLANET_LABELS="false"
HAS_AU_LABEL="false"
SHAPE_COUNT=0
HAS_FILL="false"
HAS_LINE="false"

# Check if file exists
if [ -f "$EXPECTED_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE"
elif [ -f "$EXPECTED_FILE_ALT" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE_ALT"
fi

if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$FILE_PATH")
    FILE_MTIME=$(get_file_mtime "$FILE_PATH")
    
    # Check creation time
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Validate file format (ZIP/XML)
    if check_flipchart_file "$FILE_PATH" | grep -q "valid"; then
        FILE_VALID="true"
        
        # Extract and analyze content
        TEMP_DIR=$(mktemp -d)
        if unzip -q "$FILE_PATH" -d "$TEMP_DIR" 2>/dev/null; then
            # Concatenate all XML files for easier searching
            ALL_XML=$(find "$TEMP_DIR" -name "*.xml" -exec cat {} \;)
            
            # Check for labels (case insensitive)
            if echo "$ALL_XML" | grep -qi "Sun"; then HAS_SUN_LABEL="true"; fi
            
            # Check for planets - need all 4 for full credit in this boolean
            MERCURY=$(echo "$ALL_XML" | grep -qi "Mercury" && echo 1 || echo 0)
            VENUS=$(echo "$ALL_XML" | grep -qi "Venus" && echo 1 || echo 0)
            EARTH=$(echo "$ALL_XML" | grep -qi "Earth" && echo 1 || echo 0)
            MARS=$(echo "$ALL_XML" | grep -qi "Mars" && echo 1 || echo 0)
            
            if [ $((MERCURY + VENUS + EARTH + MARS)) -eq 4 ]; then
                HAS_PLANET_LABELS="true"
            fi
            
            # Check for AU label
            if echo "$ALL_XML" | grep -qi "1 AU\|1AU\|One AU"; then HAS_AU_LABEL="true"; fi
            
            # Count Shapes (Circles/Ellipses/Shapes)
            # ActivInspire uses <AsShape>, <AsCircle>, <AsEllipse>
            SHAPE_COUNT=$(echo "$ALL_XML" | grep -o "<AsShape\|<AsCircle\|<AsEllipse" | wc -l)
            
            # Check for Fill (Yellow or Solid)
            # Look for filled="true" or specific brush colors
            # Yellow hex often #FFFF00
            if echo "$ALL_XML" | grep -qi "filled=\"true\"\|brush=\"SolidPattern\"\|#FFFF00"; then
                HAS_FILL="true"
            fi
            
            # Check for Line/Connector
            if echo "$ALL_XML" | grep -qi "<AsLine\|<AsConnector\|<AsArrow"; then
                HAS_LINE="true"
            fi
        fi
        rm -rf "$TEMP_DIR"
    fi
fi

# Create JSON result
create_result_json << EOF
{
    "file_found": $(json_bool "$FILE_FOUND"),
    "file_valid": $(json_bool "$FILE_VALID"),
    "created_during_task": $(json_bool "$CREATED_DURING_TASK"),
    "has_sun_label": $(json_bool "$HAS_SUN_LABEL"),
    "has_planet_labels": $(json_bool "$HAS_PLANET_LABELS"),
    "has_au_label": $(json_bool "$HAS_AU_LABEL"),
    "shape_count": ${SHAPE_COUNT:-0},
    "has_fill": $(json_bool "$HAS_FILL"),
    "has_line": $(json_bool "$HAS_LINE"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="