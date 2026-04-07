#!/bin/bash
echo "=== Exporting import_dxf_nema17_gasket results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

WORKSPACE_DIR="/home/ga/Documents/SolveSpace"
SLVS_FILE="$WORKSPACE_DIR/nema17_damper_3d.slvs"
STL_FILE="$WORKSPACE_DIR/nema17_damper_3d.stl"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ensure files are readable by the export process
chmod 666 "$SLVS_FILE" 2>/dev/null || true
chmod 666 "$STL_FILE" 2>/dev/null || true

# Check SLVS file
SLVS_EXISTS="false"
SLVS_CREATED_DURING_TASK="false"
SLVS_SIZE="0"

if [ -f "$SLVS_FILE" ]; then
    SLVS_EXISTS="true"
    SLVS_SIZE=$(stat -c %s "$SLVS_FILE" 2>/dev/null || echo "0")
    SLVS_MTIME=$(stat -c %Y "$SLVS_FILE" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -ge "$TASK_START" ]; then
        SLVS_CREATED_DURING_TASK="true"
    fi
fi

# Check STL file
STL_EXISTS="false"
STL_CREATED_DURING_TASK="false"
STL_SIZE="0"

if [ -f "$STL_FILE" ]; then
    STL_EXISTS="true"
    STL_SIZE=$(stat -c %s "$STL_FILE" 2>/dev/null || echo "0")
    STL_MTIME=$(stat -c %Y "$STL_FILE" 2>/dev/null || echo "0")
    if [ "$STL_MTIME" -ge "$TASK_START" ]; then
        STL_CREATED_DURING_TASK="true"
    fi
fi

# Check if application is running
APP_RUNNING="false"
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created_during_task": $SLVS_CREATED_DURING_TASK,
    "slvs_size_bytes": $SLVS_SIZE,
    "stl_exists": $STL_EXISTS,
    "stl_created_during_task": $STL_CREATED_DURING_TASK,
    "stl_size_bytes": $STL_SIZE,
    "app_was_running": $APP_RUNNING,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="