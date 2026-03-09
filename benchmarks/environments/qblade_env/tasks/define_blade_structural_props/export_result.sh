#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Execution Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(is_qblade_running)

# 3. Check Project File (.wpa)
PROJECT_PATH="/home/ga/Documents/projects/structural_design.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_MTIME=0

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_PATH")
fi

# 4. Check Report File (.txt)
REPORT_PATH="/home/ga/Documents/blade_mass.txt"
REPORT_EXISTS="false"
REPORTED_MASS=""
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Extract first numeric value found in the file
    REPORTED_MASS=$(grep -oE "[0-9]+(\.[0-9]+)?" "$REPORT_PATH" | head -1)
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH")
fi

# 5. Verify File Creation Times (Anti-Gaming)
FILES_NEW="false"
if [ "$PROJECT_MTIME" -gt "$TASK_START" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    FILES_NEW="true"
fi

# 6. Prepare Project Content for Verification
# We copy the WPA file to a temp location with permissive permissions so the python verifier can read it safely
# (The verifier runs outside the container but needs access via copy_from_env, this step prepares it inside for easy debugging if needed)
cp "$PROJECT_PATH" /tmp/verify_project.wpa 2>/dev/null || true
chmod 666 /tmp/verify_project.wpa 2>/dev/null || true

# 7. Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "reported_mass": "$REPORTED_MASS",
    "files_created_during_task": $FILES_NEW,
    "project_path": "$PROJECT_PATH"
}
EOF
)

write_result_json "$RESULT_JSON"

echo "=== Export Complete ==="