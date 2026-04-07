#!/bin/bash
set -euo pipefail

echo "=== Exporting gps_graveyard_disposal results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Agent might name the script differently, try to find the newest script in output dir
SCRIPT_PATH=$(ls -t /home/ga/GMAT_output/*.script 2>/dev/null | head -1 || echo "")
if [ -z "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="/home/ga/GMAT_output/gps_graveyard_disposal.script"
fi

REPORT_PATH="/home/ga/GMAT_output/graveyard_disposal_report.txt"

# Capture final screenshot
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

# Analyze script content
SC_DEFINED="false"
INIT_ORBIT_CORRECT="false"
TWO_BURNS="false"
PROPAGATION_LOGIC="false"

if [ -f "$SCRIPT_PATH" ]; then
    grep -qi "Create Spacecraft" "$SCRIPT_PATH" && SC_DEFINED="true" || true
    
    # Check if initial orbit matches roughly
    if grep -q "26559" "$SCRIPT_PATH" && grep -q "55.1" "$SCRIPT_PATH" && grep -q "0.0038" "$SCRIPT_PATH"; then
        INIT_ORBIT_CORRECT="true"
    fi
    
    BURN_COUNT=$(grep -ci "Create ImpulsiveBurn\|Create FiniteBurn" "$SCRIPT_PATH" || echo "0")
    if [ "$BURN_COUNT" -ge 2 ]; then
        TWO_BURNS="true"
    fi
    
    PROP_COUNT=$(grep -ci "\bPropagate " "$SCRIPT_PATH" || echo "0")
    if [ "$PROP_COUNT" -ge 2 ]; then
        PROPAGATION_LOGIC="true"
    fi
fi

# Re-run the script via GmatConsole
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Read values from report
INIT_SMA="0"; FIN_SMA="0"; TOT_DV="0"; FUEL="0"; FIN_ECC="0"; COMPLIANCE="unknown"
if [ -f "$REPORT_PATH" ]; then
    INIT_SMA=$(grep -ioP 'initial_SMA_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    FIN_SMA=$(grep -ioP 'final_SMA_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    TOT_DV=$(grep -ioP 'total_deltav_ms:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    FUEL=$(grep -ioP 'fuel_consumed_kg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "0")
    FIN_ECC=$(grep -ioP 'final_ECC:\s*\K[0-9]+\.?[0-9e+-]*' "$REPORT_PATH" | head -1 || echo "0")
    COMPLIANCE=$(grep -ioP 'compliance_status:\s*\K[a-zA-Z_]+' "$REPORT_PATH" | head -1 || echo "unknown")
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "sc_defined": $SC_DEFINED,
    "init_orbit_correct": $INIT_ORBIT_CORRECT,
    "two_burns_present": $TWO_BURNS,
    "propagation_logic": $PROPAGATION_LOGIC,
    "console_run_success": "$RUN_SUCCESS",
    "reported_init_sma": "$INIT_SMA",
    "reported_fin_sma": "$FIN_SMA",
    "reported_tot_dv": "$TOT_DV",
    "reported_fuel": "$FUEL",
    "reported_fin_ecc": "$FIN_ECC",
    "reported_compliance": "$COMPLIANCE",
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