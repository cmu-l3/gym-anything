#!/bin/bash
echo "=== Exporting bookcase_equal_spacing result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

SLVS_PATH="/home/ga/Documents/SolveSpace/bookcase.slvs"
DXF_PATH="/home/ga/Documents/SolveSpace/bookcase.dxf"

SLVS_EXISTS="false"
DXF_EXISTS="false"
SLVS_CREATED="false"
DXF_CREATED="false"

# Check SLVS file
if [ -f "$SLVS_PATH" ]; then
    SLVS_EXISTS="true"
    SLVS_MTIME=$(stat -c %Y "$SLVS_PATH" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -ge "$TASK_START" ]; then
        SLVS_CREATED="true"
    fi
fi

# Check DXF file
if [ -f "$DXF_PATH" ]; then
    DXF_EXISTS="true"
    DXF_MTIME=$(stat -c %Y "$DXF_PATH" 2>/dev/null || echo "0")
    if [ "$DXF_MTIME" -ge "$TASK_START" ]; then
        DXF_CREATED="true"
    fi
fi

# Check application status
APP_RUNNING="false"
if pgrep -f "solvespace" > /dev/null; then
    APP_RUNNING="true"
fi

# Write results to JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_created": $SLVS_CREATED,
    "dxf_exists": $DXF_EXISTS,
    "dxf_created": $DXF_CREATED,
    "app_was_running": $APP_RUNNING
}
EOF

chmod 666 /tmp/task_result.json

echo "=== Export complete ==="