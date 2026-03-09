#!/bin/bash
echo "=== Exporting blade_root_transition_design results ==="

# 1. Record end time and retrieve start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check output files
GEO_FILE="/home/ga/Documents/projects/root_transition_geometry.dat"
PROJ_FILE="/home/ga/Documents/projects/blade_design_task.wpa"

# Initialize status variables
GEO_EXISTS="false"
GEO_SIZE="0"
GEO_CREATED_DURING_TASK="false"
PROJ_EXISTS="false"
PROJ_SIZE="0"
PROJ_CREATED_DURING_TASK="false"

# Check Geometry File
if [ -f "$GEO_FILE" ]; then
    GEO_EXISTS="true"
    GEO_SIZE=$(stat -c%s "$GEO_FILE")
    GEO_MTIME=$(stat -c%Y "$GEO_FILE")
    
    if [ "$GEO_MTIME" -gt "$TASK_START" ]; then
        GEO_CREATED_DURING_TASK="true"
    fi
fi

# Check Project File
if [ -f "$PROJ_FILE" ]; then
    PROJ_EXISTS="true"
    PROJ_SIZE=$(stat -c%s "$PROJ_FILE")
    PROJ_MTIME=$(stat -c%Y "$PROJ_FILE")
    
    if [ "$PROJ_MTIME" -gt "$TASK_START" ]; then
        PROJ_CREATED_DURING_TASK="true"
    fi
fi

# 3. Take final screenshot for VLM/Evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON result
# Note: We do NOT read the file content into JSON here to avoid escaping issues.
# The verifier will copy the file out of the environment to inspect it.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "geometry_file_exists": $GEO_EXISTS,
    "geometry_file_size": $GEO_SIZE,
    "geometry_created_during_task": $GEO_CREATED_DURING_TASK,
    "project_file_exists": $PROJ_EXISTS,
    "project_file_size": $PROJ_SIZE,
    "project_created_during_task": $PROJ_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="