#!/bin/bash
set -e

echo "=== Exporting create_network_diagram task result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/network_task_end.png 2>/dev/null || true

# Check for the diagram file - MUST be exact filename, no fallbacks
DIAGRAM_FILE="/home/ga/Desktop/office_network.drawio"
FOUND="false"
FILE_EXISTS="false"
FILE_SIZE=0
NUM_SHAPES=0
NUM_CONNECTIONS=0
VALID_CONNECTIONS=0

# Network element detection
HAS_CLOUD="false"
HAS_ROUTER="false"
HAS_SWITCH="false"
HAS_COMPUTER="false"
HAS_SERVER="false"
NUM_COMPUTERS=0

# Only accept the exact expected filename - NO FALLBACKS
if [ -f "$DIAGRAM_FILE" ]; then
    FILE_EXISTS="true"
    FOUND="true"
    FILE_SIZE=$(stat --format=%s "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    echo "Found diagram file: $DIAGRAM_FILE (size: $FILE_SIZE bytes)"
else
    echo "ERROR: Expected file not found: $DIAGRAM_FILE"
    echo "Task requires saving as 'office_network.drawio' on Desktop"
fi

# If file exists, analyze its content with strict validation
if [ "$FILE_EXISTS" = "true" ] && [ -f "$DIAGRAM_FILE" ]; then
    echo "Analyzing diagram content..."

    # Count shapes (cells with vertex="1")
    NUM_SHAPES=$(grep -c 'vertex="1"' "$DIAGRAM_FILE" 2>/dev/null | tr -d '\n' || echo "0")

    # Count connections (cells with edge="1")
    NUM_CONNECTIONS=$(grep -c 'edge="1"' "$DIAGRAM_FILE" 2>/dev/null | tr -d '\n' || echo "0")

    # STRICT: Count only VALID connections (edges with both source and target)
    # Use awk to handle multi-line XML elements properly
    VALID_CONNECTIONS=$(awk '
        BEGIN { count = 0; in_edge = 0; has_source = 0; has_target = 0 }
        /edge="1"/ { in_edge = 1; has_source = 0; has_target = 0 }
        in_edge && /source="[^"]+"/ { has_source = 1 }
        in_edge && /target="[^"]+"/ { has_target = 1 }
        in_edge && />/ {
            if (has_source && has_target) count++
            in_edge = 0
        }
        /<\/mxCell>/ || /\/>/ {
            if (in_edge && has_source && has_target) count++
            in_edge = 0
        }
        END { print count }
    ' "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    # Clean up the value
    VALID_CONNECTIONS=$(printf '%d' "$VALID_CONNECTIONS" 2>/dev/null || echo "0")

    # Check for network elements - STRICT: only match in value= attribute (visible text)
    # Cloud (Internet) - check both shape style and text label
    if grep -qE 'style="[^"]*cloud[^"]*"' "$DIAGRAM_FILE" 2>/dev/null; then
        HAS_CLOUD="true"
    fi

    # STRICT text detection: Only match text in value= attribute
    HAS_INTERNET_TEXT=$(grep -qiE 'value="[^"]*internet[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_ROUTER_TEXT=$(grep -qiE 'value="[^"]*(router|firewall)[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_SWITCH_TEXT=$(grep -qiE 'value="[^"]*switch[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_COMPUTER_TEXT=$(grep -qiE 'value="[^"]*(computer|workstation|pc[0-9])[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_SERVER_TEXT=$(grep -qiE 'value="[^"]*server[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")

    # Count number of PC/Computer/Workstation elements (task requires PC1, PC2, PC3)
    NUM_COMPUTERS=$(grep -oiE 'value="[^"]*(pc[0-9]*|computer[0-9]*|workstation[0-9]*)[^"]*"' "$DIAGRAM_FILE" 2>/dev/null | wc -l || echo "0")
    NUM_COMPUTERS=$(printf '%d' "$NUM_COMPUTERS" 2>/dev/null || echo "0")

    # Set shape flags based on text labels (text labels are the primary way to identify elements)
    if [ "$HAS_INTERNET_TEXT" = "true" ] || [ "$HAS_CLOUD" = "true" ]; then
        HAS_CLOUD="true"
    fi
    if [ "$HAS_ROUTER_TEXT" = "true" ]; then
        HAS_ROUTER="true"
    fi
    if [ "$HAS_SWITCH_TEXT" = "true" ]; then
        HAS_SWITCH="true"
    fi
    if [ "$HAS_COMPUTER_TEXT" = "true" ]; then
        HAS_COMPUTER="true"
    fi
    if [ "$HAS_SERVER_TEXT" = "true" ]; then
        HAS_SERVER="true"
    fi

    echo "Analysis results:"
    echo "  - Shapes: $NUM_SHAPES"
    echo "  - Connections (raw): $NUM_CONNECTIONS"
    echo "  - Valid connections (with source+target): $VALID_CONNECTIONS"
    echo "  - Has cloud/internet: $HAS_CLOUD (text: $HAS_INTERNET_TEXT)"
    echo "  - Has router: $HAS_ROUTER (text: $HAS_ROUTER_TEXT)"
    echo "  - Has switch: $HAS_SWITCH (text: $HAS_SWITCH_TEXT)"
    echo "  - Has computer: $HAS_COMPUTER (text: $HAS_COMPUTER_TEXT, count: $NUM_COMPUTERS)"
    echo "  - Has server: $HAS_SERVER (text: $HAS_SERVER_TEXT)"
fi

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_drawio_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")

# Create JSON result - use VALID_CONNECTIONS as primary connection count
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "file_exists": $FILE_EXISTS,
    "file_path": "$DIAGRAM_FILE",
    "file_size": $FILE_SIZE,
    "num_shapes": $NUM_SHAPES,
    "num_connections": $VALID_CONNECTIONS,
    "raw_edge_count": $NUM_CONNECTIONS,
    "has_cloud": $HAS_CLOUD,
    "has_router": $HAS_ROUTER,
    "has_switch": $HAS_SWITCH,
    "has_computer": $HAS_COMPUTER,
    "num_computers": $NUM_COMPUTERS,
    "has_server": $HAS_SERVER,
    "has_internet_text": ${HAS_INTERNET_TEXT:-false},
    "has_router_text": ${HAS_ROUTER_TEXT:-false},
    "has_switch_text": ${HAS_SWITCH_TEXT:-false},
    "has_computer_text": ${HAS_COMPUTER_TEXT:-false},
    "has_server_text": ${HAS_SERVER_TEXT:-false},
    "initial_file_count": $INITIAL_COUNT,
    "current_file_count": $CURRENT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
