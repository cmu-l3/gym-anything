#!/bin/bash
set -euo pipefail

echo "=== Exporting lunar_orbit_stability_mascons results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/lunar_stability.script"
REPORT_PATH="/home/ga/GMAT_output/lunar_stability_report.txt"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Helper to check file existence and timestamps
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

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Parse report variables (case insensitive, robust grep)
CIRC_LIFE="-1"
CIRC_MIN_ALT="9999"
FROZ_LIFE="-1"
FROZ_MIN_ALT="-9999"

if [ -f "$REPORT_PATH" ]; then
    CIRC_LIFE=$(grep -ioP 'circular_lifetime_days:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    CIRC_MIN_ALT=$(grep -ioP 'circular_min_altitude_km:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "9999")
    FROZ_LIFE=$(grep -ioP 'frozen_lifetime_days:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    FROZ_MIN_ALT=$(grep -ioP 'frozen_min_altitude_km:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-9999")
    
    # Fallback to catch potential negative numbers without the exact label regex constraint
    if [ "$CIRC_MIN_ALT" = "9999" ]; then
        CIRC_MIN_ALT=$(grep -io 'circular_min_altitude_km.*' "$REPORT_PATH" | grep -oE '-?[0-9]+\.?[0-9]*' | head -1 || echo "9999")
    fi
fi

# Re-run the script in console mode to verify it's a valid GMAT script
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 300 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Build JSON export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "circular_lifetime_days": "$CIRC_LIFE",
    "circular_min_altitude_km": "$CIRC_MIN_ALT",
    "frozen_lifetime_days": "$FROZ_LIFE",
    "frozen_min_altitude_km": "$FROZ_MIN_ALT",
    "console_run_success": "$RUN_SUCCESS",
    "script_path": "$SCRIPT_PATH",
    "report_path": "$REPORT_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json
echo "=== Export Done ==="