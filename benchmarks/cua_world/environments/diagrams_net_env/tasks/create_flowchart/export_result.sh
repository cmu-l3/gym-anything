#!/bin/bash
set -e

echo "=== Exporting create_flowchart task result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/flowchart_task_end.png 2>/dev/null || true

# Check for the diagram file - MUST be exact filename, no fallbacks
DIAGRAM_FILE="/home/ga/Desktop/login_flowchart.drawio"
FOUND="false"
FILE_EXISTS="false"
FILE_SIZE=0
NUM_SHAPES=0
NUM_CONNECTIONS=0
VALID_CONNECTIONS=0
HAS_TERMINAL="false"
HAS_PROCESS="false"
HAS_DECISION="false"

# Only accept the exact expected filename - NO FALLBACKS
if [ -f "$DIAGRAM_FILE" ]; then
    FILE_EXISTS="true"
    FOUND="true"
    FILE_SIZE=$(stat --format=%s "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    echo "Found diagram file: $DIAGRAM_FILE (size: $FILE_SIZE bytes)"
else
    echo "ERROR: Expected file not found: $DIAGRAM_FILE"
    echo "Task requires saving as 'login_flowchart.drawio' on Desktop"
fi

# If file exists, analyze its content with strict validation
if [ "$FILE_EXISTS" = "true" ] && [ -f "$DIAGRAM_FILE" ]; then
    echo "Analyzing diagram content..."

    # Count mxCell elements (shapes and connections)
    TOTAL_CELLS=$(grep -o '<mxCell' "$DIAGRAM_FILE" 2>/dev/null | wc -l || echo "0")

    # Count shapes (cells with vertex="1") - exclude root cells (id="0" and id="1")
    # Only count cells that have actual geometry (are visible shapes)
    NUM_SHAPES=$(grep -E 'vertex="1".*<mxGeometry' "$DIAGRAM_FILE" 2>/dev/null | wc -l || echo "0")

    # If the above doesn't work, fall back to simpler count but subtract 2 for root cells
    if [ "$NUM_SHAPES" -eq 0 ]; then
        RAW_SHAPES=$(grep -c 'vertex="1"' "$DIAGRAM_FILE" 2>/dev/null | tr -d '\n' || echo "0")
        # Root mxGraphModel has 2 internal cells, so actual shapes = raw - those internal ones
        # But we'll use the raw count if we can't do better
        NUM_SHAPES=$RAW_SHAPES
    fi

    # Count connections (cells with edge="1")
    NUM_CONNECTIONS=$(grep -c 'edge="1"' "$DIAGRAM_FILE" 2>/dev/null | tr -d '\n' || echo "0")

    # STRICT: Count only VALID connections (edges with both source and target)
    # This ensures we don't count disconnected arrows
    # Use awk to handle multi-line XML elements properly
    # An edge is valid if the mxCell element has edge="1", source="..." and target="..."
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

    # Check for shape types by looking at style attributes
    # Terminal shapes: ellipses are standard flowchart terminals
    if grep -qE 'style="[^"]*ellipse[^"]*"' "$DIAGRAM_FILE" 2>/dev/null; then
        HAS_TERMINAL="true"
    fi

    # Process shapes (rectangles) - look for standard rectangle with whiteSpace=wrap
    if grep -qE 'style="[^"]*rounded=0[^"]*whiteSpace=wrap[^"]*"' "$DIAGRAM_FILE" 2>/dev/null; then
        HAS_PROCESS="true"
    elif grep -qE 'vertex="1"' "$DIAGRAM_FILE" 2>/dev/null && ! grep -qE 'ellipse|rhombus' "$DIAGRAM_FILE" 2>/dev/null; then
        # If we have vertices but no special shapes, assume process shapes exist
        HAS_PROCESS="true"
    fi

    # Decision shapes (diamonds) - look for rhombus style
    if grep -qE 'style="[^"]*rhombus[^"]*"' "$DIAGRAM_FILE" 2>/dev/null; then
        HAS_DECISION="true"
    fi

    # STRICT text detection: Only match text in value= attribute (actual shape content)
    # This prevents matching metadata, comments, or style attributes
    HAS_START=$(grep -qiE 'value="[^"]*start[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_END=$(grep -qiE 'value="[^"]*end[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_USERNAME=$(grep -qiE 'value="[^"]*username[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_PASSWORD=$(grep -qiE 'value="[^"]*password[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_VALID=$(grep -qiE 'value="[^"]*valid[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_LOGIN=$(grep -qiE 'value="[^"]*(login|success)[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")
    HAS_ERROR=$(grep -qiE 'value="[^"]*error[^"]*"' "$DIAGRAM_FILE" 2>/dev/null && echo "true" || echo "false")

    echo "Analysis results:"
    echo "  - Total cells: $TOTAL_CELLS"
    echo "  - Shapes (vertices): $NUM_SHAPES"
    echo "  - Connections (edges): $NUM_CONNECTIONS"
    echo "  - Valid connections (with source+target): $VALID_CONNECTIONS"
    echo "  - Has terminal shapes (ellipse): $HAS_TERMINAL"
    echo "  - Has process shapes (rectangle): $HAS_PROCESS"
    echo "  - Has decision shapes (rhombus): $HAS_DECISION"
    echo "  - Text labels found: Start=$HAS_START, End=$HAS_END, Username=$HAS_USERNAME, Password=$HAS_PASSWORD"
fi

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_drawio_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")

# Create JSON result with temp file pattern
# Use VALID_CONNECTIONS as the primary connection count
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
    "has_terminal": $HAS_TERMINAL,
    "has_process": $HAS_PROCESS,
    "has_decision": $HAS_DECISION,
    "has_start_text": ${HAS_START:-false},
    "has_end_text": ${HAS_END:-false},
    "has_username_text": ${HAS_USERNAME:-false},
    "has_password_text": ${HAS_PASSWORD:-false},
    "has_valid_text": ${HAS_VALID:-false},
    "has_login_text": ${HAS_LOGIN:-false},
    "has_error_text": ${HAS_ERROR:-false},
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
