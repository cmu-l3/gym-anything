#!/bin/bash
set -euo pipefail

echo "=== Exporting interstellar_probe_kinematics_forecast results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/interstellar_forecast.script"
REPORT_PATH="/home/ga/GMAT_output/probe_kinematics_2050.txt"

take_screenshot /tmp/task_final.png

check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during=$([ "$mtime" -ge "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
REPORT_STATS=$(check_file "$REPORT_PATH")

CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 300 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_interstellar.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

REPORT_STATS_RERUN=$(check_file "$REPORT_PATH")
APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

V1_DIST="0"; V1_VEL="0"; V2_DIST="0"; V2_VEL="0"; NH_DIST="0"; NH_VEL="0"
FASTEST="unknown"; FURTHEST="unknown"

if [ -f "$REPORT_PATH" ]; then
    V1_DIST=$(grep -i -oP 'V1_distance_AU:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    V1_VEL=$(grep -i -oP 'V1_velocity_kms:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    V2_DIST=$(grep -i -oP 'V2_distance_AU:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    V2_VEL=$(grep -i -oP 'V2_velocity_kms:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    NH_DIST=$(grep -i -oP 'NH_distance_AU:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    NH_VEL=$(grep -i -oP 'NH_velocity_kms:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    FASTEST=$(grep -i -oP 'fastest_probe:\s*\K[A-Za-z0-9_]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "unknown")
    FURTHEST=$(grep -i -oP 'furthest_probe:\s*\K[A-Za-z0-9_]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "unknown")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "report_file_rerun": $REPORT_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "v1_dist": "$V1_DIST",
    "v1_vel": "$V1_VEL",
    "v2_dist": "$V2_DIST",
    "v2_vel": "$V2_VEL",
    "nh_dist": "$NH_DIST",
    "nh_vel": "$NH_VEL",
    "fastest_probe": "$FASTEST",
    "furthest_probe": "$FURTHEST",
    "script_path": "$SCRIPT_PATH",
    "report_path": "$REPORT_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="