#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# CHECK 1: CLEANED DATA FILE
# ------------------------------------------------------------------
# We look for ANY .dat file in ~/Documents created during the task
# that looks "clean" (no commas in data lines)

CLEAN_FILE_FOUND="false"
CLEAN_FILE_PATH=""
CLEAN_FILE_VALID="false"

# Find files modified/created after task start
POSSIBLE_FILES=$(find /home/ga/Documents -type f -name "*.dat" -newermt "@$TASK_START" 2>/dev/null)

for f in $POSSIBLE_FILES; do
    # Check if file has commas (bad)
    if ! grep -q "," "$f"; then
        # Check if it has at least 20 lines
        LINE_COUNT=$(wc -l < "$f")
        if [ "$LINE_COUNT" -gt 20 ]; then
            # Check if it looks like coordinate data (2 numbers per line)
            # Sample a line from the middle
            SAMPLE=$(sed -n '20p' "$f")
            if [[ "$SAMPLE" =~ ^[[:space:]]*[-+]?[0-9]*\.?[0-9]+[[:space:]]+[-+]?[0-9]*\.?[0-9]+ ]]; then
                CLEAN_FILE_FOUND="true"
                CLEAN_FILE_PATH="$f"
                CLEAN_FILE_VALID="true"
                break
            fi
        fi
    fi
done

# ------------------------------------------------------------------
# CHECK 2: QBLADE PROJECT FILE
# ------------------------------------------------------------------
PROJECT_PATH="/home/ga/Documents/projects/falcon_design.wpa"
PROJECT_EXISTS="false"
AIRFOIL_IN_PROJECT="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    
    # Check if file was created/modified during task
    FILE_TIME=$(stat -c %Y "$PROJECT_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        # Check content for the airfoil name "Project_Falcon_Foil"
        # QBlade files are text/xml/ini, usually readable
        if grep -qi "Project_Falcon_Foil" "$PROJECT_PATH" || grep -qi "Project Falcon" "$PROJECT_PATH"; then
            AIRFOIL_IN_PROJECT="true"
        fi
        
        # Also check for characteristic coordinate data (e.g. 0.99639)
        # to ensure it wasn't just an empty project named correctly
        if grep -q "0.99639" "$PROJECT_PATH"; then
             AIRFOIL_IN_PROJECT="true"
        fi
    fi
fi

# ------------------------------------------------------------------
# CHECK 3: APP STATE
# ------------------------------------------------------------------
APP_RUNNING=$(is_qblade_running)
APP_RUNNING_BOOL="false"
if [ "$APP_RUNNING" -gt 0 ]; then
    APP_RUNNING_BOOL="true"
fi

# ------------------------------------------------------------------
# PREPARE JSON RESULT
# ------------------------------------------------------------------
cat > /tmp/task_result.json << EOF
{
    "clean_file_found": $CLEAN_FILE_FOUND,
    "clean_file_path": "$CLEAN_FILE_PATH",
    "clean_file_valid": $CLEAN_FILE_VALID,
    "project_exists": $PROJECT_EXISTS,
    "project_path": "$PROJECT_PATH",
    "airfoil_found_in_project": $AIRFOIL_IN_PROJECT,
    "app_running": $APP_RUNNING_BOOL,
    "task_duration": $(($NOW - $TASK_START))
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json