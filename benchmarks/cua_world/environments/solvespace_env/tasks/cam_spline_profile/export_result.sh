#!/bin/bash
echo "=== Exporting cam_spline_profile task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Paths and initial vars
TARGET_FILE="/home/ga/Documents/SolveSpace/cam_plate.slvs"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_AFTER_START="false"
HAS_CUBIC_SPLINE="false"
SPLINE_POINTS="0"
HAS_EXTRUSION="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0")
    MTIME=$(stat -c%Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$MTIME" -gt "$START_TIME" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi

    # Parse plain text .slvs file for geometric entities
    # Cubic splines requests are type 400 (open) or 500 (periodic/closed)
    # Cubic spline entities are type 12000 or 12001
    CUBIC_REQ=$(grep -c "Request.type=[45]00" "$TARGET_FILE" 2>/dev/null || echo "0")
    CUBIC_ENT=$(grep -c "Entity.type=1200[01]" "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$CUBIC_REQ" -gt 0 ] || [ "$CUBIC_ENT" -gt 0 ]; then
        HAS_CUBIC_SPLINE="true"
    fi

    # Count 2D point entities (Entity.type=2001) as a proxy for spline control points
    SPLINE_POINTS=$(grep -c "Entity.type=2001" "$TARGET_FILE" 2>/dev/null || echo "0")

    # Check for Extrusion Group (type 5003, 5100, or 5101 depending on solvespace version)
    # Or simply check for the word 'extrude' in group names
    EXTRUDE_GROUPS=$(grep -c -i "extrude" "$TARGET_FILE" 2>/dev/null || echo "0")
    GROUP_TYPES=$(grep -c "Group.type=510[01]\|Group.type=5003" "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$EXTRUDE_GROUPS" -gt 0 ] || [ "$GROUP_TYPES" -gt 0 ]; then
        HAS_EXTRUSION="true"
    fi
fi

# Determine if the application was still running
APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "task_end_time": $END_TIME,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "has_cubic_spline": $HAS_CUBIC_SPLINE,
    "spline_points_count": $SPLINE_POINTS,
    "has_extrusion_group": $HAS_EXTRUSION,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to standard location accessible by copy_from_env
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="