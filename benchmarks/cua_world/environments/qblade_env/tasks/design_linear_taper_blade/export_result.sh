#!/bin/bash
set -e

echo "=== Exporting design_linear_taper_blade result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
PROJECT_PATH="/home/ga/Documents/projects/tsr7_rotor.wpa"
GEOMETRY_PATH="/home/ga/Documents/tsr7_geometry.txt"
RESULTS_PATH="/home/ga/Documents/tsr7_bem_results.txt"

# Check Project File
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
else
    PROJECT_EXISTS="false"
    PROJECT_SIZE=0
    PROJECT_MTIME=0
fi

# Check Geometry File
if [ -f "$GEOMETRY_PATH" ]; then
    GEOMETRY_EXISTS="true"
    GEOMETRY_SIZE=$(stat -c %s "$GEOMETRY_PATH")
    GEOMETRY_MTIME=$(stat -c %Y "$GEOMETRY_PATH")
else
    GEOMETRY_EXISTS="false"
    GEOMETRY_SIZE=0
    GEOMETRY_MTIME=0
fi

# Check Results File
if [ -f "$RESULTS_PATH" ]; then
    RESULTS_EXISTS="true"
    RESULTS_SIZE=$(stat -c %s "$RESULTS_PATH")
    RESULTS_MTIME=$(stat -c %Y "$RESULTS_PATH")
else
    RESULTS_EXISTS="false"
    RESULTS_SIZE=0
    RESULTS_MTIME=0
fi

# Check timestamps (Anti-Gaming)
FILES_FRESH="true"
if [ "$PROJECT_EXISTS" = "true" ] && [ "$PROJECT_MTIME" -lt "$TASK_START" ]; then FILES_FRESH="false"; fi
if [ "$GEOMETRY_EXISTS" = "true" ] && [ "$GEOMETRY_MTIME" -lt "$TASK_START" ]; then FILES_FRESH="false"; fi
if [ "$RESULTS_EXISTS" = "true" ] && [ "$RESULTS_MTIME" -lt "$TASK_START" ]; then FILES_FRESH="false"; fi

# Check if QBlade is running
QBLADE_RUNNING=$(is_qblade_running)
APP_RUNNING="false"
if [ "$QBLADE_RUNNING" -gt "0" ]; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
# We rely on verifier.py to actually read/parse the content of the text files using copy_from_env
# So we just report metadata here.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "geometry_exists": $GEOMETRY_EXISTS,
    "geometry_size": $GEOMETRY_SIZE,
    "results_exists": $RESULTS_EXISTS,
    "results_size": $RESULTS_SIZE,
    "files_fresh": $FILES_FRESH,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "project_path": "$PROJECT_PATH",
    "geometry_path": "$GEOMETRY_PATH",
    "results_path": "$RESULTS_PATH"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="