#!/bin/bash
echo "=== Exporting Digital Twin task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Existence & Metadata
PROJECT_FILE="/home/ga/Documents/projects/legacy_v1_reconstruction.wpa"
CHORD_FILE="/home/ga/Documents/projects/chord_dist.dat"
TWIST_FILE="/home/ga/Documents/projects/twist_dist.dat"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Function to check file status
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local fsize=$(stat -c%s "$fpath")
        local fmtime=$(stat -c%Y "$fpath")
        local created_during=$([ "$fmtime" -gt "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $fsize, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

PROJECT_STATUS=$(check_file "$PROJECT_FILE")
CHORD_STATUS=$(check_file "$CHORD_FILE")
TWIST_STATUS=$(check_file "$TWIST_FILE")

# 3. Check Application State
APP_RUNNING=$(is_qblade_running)
QBLADE_WAS_RUNNING=$([ "$APP_RUNNING" -gt "0" ] && echo "true" || echo "false")

# 4. Check Logs for Airfoil Generation (Heuristic)
# QBlade logs to stdout/stderr which we redirected to /tmp/qblade_task.log in launch_qblade
LOG_FILE="/tmp/qblade_task.log"
GENERATED_4424="false"
GENERATED_4412="false"

if [ -f "$LOG_FILE" ]; then
    # QBlade logs are sparse, but we might see file writes or object names if verbose
    # This is a weak signal, primary verification is the geometric data output
    if grep -qi "4424" "$LOG_FILE" || grep -qi "NACA.*4424" "$LOG_FILE"; then
        GENERATED_4424="true"
    fi
    if grep -qi "4412" "$LOG_FILE" || grep -qi "NACA.*4412" "$LOG_FILE"; then
        GENERATED_4412="true"
    fi
fi

# 5. Compile Result JSON
# We don't read the .dat files here; we let python verifier pull them via copy_from_env
# because parsing floating point data in bash is painful and error-prone.

cat > /tmp/task_result.json << EOF
{
    "project_file": $PROJECT_STATUS,
    "chord_file": $CHORD_STATUS,
    "twist_file": $TWIST_STATUS,
    "qblade_running": $QBLADE_WAS_RUNNING,
    "logs_mention_4424": $GENERATED_4424,
    "logs_mention_4412": $GENERATED_4412,
    "timestamp": $(date +%s)
}
EOF

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "Export completed. Result:"
cat /tmp/task_result.json