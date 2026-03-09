#!/bin/bash
echo "=== Exporting create_new_project result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check for expected project file
PROJECT_DIR="/home/ga/GIS_Data/projects"
EXPECTED_FILE="$PROJECT_DIR/my_first_project.qgs"
EXPECTED_FILE_QGZ="$PROJECT_DIR/my_first_project.qgz"

INITIAL_COUNT=$(cat /tmp/initial_project_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$PROJECT_DIR"/*.qgs "$PROJECT_DIR"/*.qgz 2>/dev/null | wc -l || echo "0")

# Check for the expected project file
FOUND="false"
PROJECT_PATH=""
PROJECT_SIZE=0
PROJECT_VALID="false"

if [ -f "$EXPECTED_FILE" ]; then
    FOUND="true"
    PROJECT_PATH="$EXPECTED_FILE"
    PROJECT_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    # Validate it's a proper QGS file (XML)
    if head -1 "$EXPECTED_FILE" 2>/dev/null | grep -q '<?xml'; then
        PROJECT_VALID="true"
    fi
elif [ -f "$EXPECTED_FILE_QGZ" ]; then
    FOUND="true"
    PROJECT_PATH="$EXPECTED_FILE_QGZ"
    PROJECT_SIZE=$(stat -c%s "$EXPECTED_FILE_QGZ" 2>/dev/null || echo "0")
    # QGZ files are zip archives
    if file "$EXPECTED_FILE_QGZ" 2>/dev/null | grep -qi 'zip'; then
        PROJECT_VALID="true"
    fi
fi

# Also check for any new project files in case user used different name
if [ "$FOUND" = "false" ]; then
    # Find any recently created .qgs or .qgz file
    RECENT_PROJECT=$(find "$PROJECT_DIR" -maxdepth 1 \( -name "*.qgs" -o -name "*.qgz" \) -mmin -5 2>/dev/null | head -1)
    if [ -n "$RECENT_PROJECT" ]; then
        PROJECT_PATH="$RECENT_PROJECT"
        PROJECT_SIZE=$(stat -c%s "$RECENT_PROJECT" 2>/dev/null || echo "0")
        # Check validity
        if [[ "$RECENT_PROJECT" == *.qgs ]] && head -1 "$RECENT_PROJECT" 2>/dev/null | grep -q '<?xml'; then
            PROJECT_VALID="true"
        elif [[ "$RECENT_PROJECT" == *.qgz ]] && file "$RECENT_PROJECT" 2>/dev/null | grep -qi 'zip'; then
            PROJECT_VALID="true"
        fi
    fi
fi

# Close QGIS
if is_qgis_running; then
    wid=$(get_qgis_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
    fi
    safe_xdotool ga :1 key ctrl+q
    sleep 2
    # Force kill if still running
    kill_qgis ga 2>/dev/null || true
fi

# Create JSON result using temp file pattern (avoid permission issues)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "expected_found": $FOUND,
    "project_path": "$PROJECT_PATH",
    "project_size_bytes": $PROJECT_SIZE,
    "project_valid": $PROJECT_VALID,
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
