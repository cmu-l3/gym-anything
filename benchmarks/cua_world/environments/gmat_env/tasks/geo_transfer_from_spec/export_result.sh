#!/bin/bash
set -euo pipefail

echo "=== Exporting geo_transfer_from_spec results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/geo_transfer.script"
RESULTS_PATH="/home/ga/GMAT_output/geo_transfer_results.txt"

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
RESULTS_STATS=$(check_file "$RESULTS_PATH")

# Re-run through GmatConsole for anti-gaming
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_geo.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# After re-run, check results file again
RESULTS_STATS_RERUN=$(check_file "$RESULTS_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract values from results file if it exists
DV2_VAL="0"
GEO_SMA_VAL="0"
GEO_ECC_VAL="0"
GEO_INC_VAL="0"
TOTAL_DV_VAL="0"
if [ -f "$RESULTS_PATH" ]; then
    DV2_VAL=$(grep -oP 'DeltaV2_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    GEO_SMA_VAL=$(grep -oP 'GEO_SMA_km:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    GEO_ECC_VAL=$(grep -oP 'GEO_ECC:\s*\K[0-9]+\.?[0-9e+-]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    GEO_INC_VAL=$(grep -oP 'GEO_INC_deg:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    TOTAL_DV_VAL=$(grep -oP 'TotalDeltaV_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Check if DifferentialCorrector is used in script
DC_USED="false"
if [ -f "$SCRIPT_PATH" ]; then
    grep -q "DifferentialCorrector\|Target\|Vary\|Achieve" "$SCRIPT_PATH" 2>/dev/null && DC_USED="true" || DC_USED="false"
fi

# Check spec file was read (timestamp check — if spec file was accessed)
SPEC_EXISTS="false"
[ -f "/home/ga/Desktop/geo_sat_specs.txt" ] && SPEC_EXISTS="true"

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "results_file_rerun": $RESULTS_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "spec_file_exists": $SPEC_EXISTS,
    "dc_used_in_script": $DC_USED,
    "deltav2_mps": "$DV2_VAL",
    "total_deltav_mps": "$TOTAL_DV_VAL",
    "geo_sma_km": "$GEO_SMA_VAL",
    "geo_ecc": "$GEO_ECC_VAL",
    "geo_inc_deg": "$GEO_INC_VAL",
    "script_path": "$SCRIPT_PATH",
    "results_path": "$RESULTS_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="
