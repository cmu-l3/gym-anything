#!/bin/bash
set -euo pipefail

echo "=== Exporting lunar_resonant_orbit_design results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/lunar_resonant_orbit.script"
REPORT_PATH="/home/ga/GMAT_output/resonance_stability_report.txt"

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

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract values from report file
INIT_SMA="0"; INIT_PER="0"; FIN_SMA="0"; FIN_PER="0"; PERIGEE="0"; ECC="0"; MOON_INC="NO"; STAB="UNKNOWN"
if [ -f "$REPORT_PATH" ]; then
    INIT_SMA=$(grep -ioP 'initial_SMA_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    INIT_PER=$(grep -ioP 'initial_period_days:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    FIN_SMA=$(grep -ioP 'final_SMA_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    FIN_PER=$(grep -ioP 'final_period_days:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    PERIGEE=$(grep -ioP 'perigee_altitude_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    ECC=$(grep -ioP 'eccentricity:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    MOON_INC=$(grep -ioP 'moon_gravity_included:\s*\K[A-Za-z]+' "$REPORT_PATH" | head -1 || echo "NO")
    STAB=$(grep -ioP 'stability_assessment:\s*\K[A-Za-z]+' "$REPORT_PATH" | head -1 || echo "UNKNOWN")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "reported_initial_sma_km": "$INIT_SMA",
    "reported_initial_period_days": "$INIT_PER",
    "reported_final_sma_km": "$FIN_SMA",
    "reported_final_period_days": "$FIN_PER",
    "reported_perigee_altitude_km": "$PERIGEE",
    "reported_eccentricity": "$ECC",
    "reported_moon_gravity_included": "$MOON_INC",
    "reported_stability_assessment": "$STAB",
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