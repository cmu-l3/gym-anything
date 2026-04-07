#!/bin/bash
set -euo pipefail

echo "=== Exporting debris_compliance_batch results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/debris_batch_analysis.script"
REPORT_PATH="/home/ga/GMAT_output/debris_compliance_report.txt"

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

# Re-run script via GmatConsole
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 600 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_debris.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

REPORT_STATS_RERUN=$(check_file "$REPORT_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Parse compliance report to count COMPLIANT/NON_COMPLIANT entries
COMPLIANT_COUNT=0
NONCOMPLIANT_COUNT=0
SAT_A_STATUS="unknown"; SAT_B_STATUS="unknown"; SAT_C_STATUS="unknown"
SAT_D_STATUS="unknown"; SAT_E_STATUS="unknown"
REPORT_FIELD_COUNT=0

if [ -f "$REPORT_PATH" ]; then
    COMPLIANT_COUNT=$(grep -c "COMPLIANT" "$REPORT_PATH" 2>/dev/null || echo "0")
    NONCOMPLIANT_COUNT=$(grep -c "NON_COMPLIANT" "$REPORT_PATH" 2>/dev/null || echo "0")
    # Subtract overlap (NON_COMPLIANT contains COMPLIANT as substring)
    COMPLIANT_COUNT=$((COMPLIANT_COUNT - NONCOMPLIANT_COUNT))

    grep -q "SAT_A.*COMPLIANT\|COMPLIANT.*SAT_A" "$REPORT_PATH" 2>/dev/null && SAT_A_STATUS="compliant" || true
    grep -q "SAT_A.*NON_COMPLIANT\|NON_COMPLIANT.*SAT_A" "$REPORT_PATH" 2>/dev/null && SAT_A_STATUS="non_compliant" || true
    grep -q "SAT_B.*NON_COMPLIANT\|NON_COMPLIANT.*SAT_B" "$REPORT_PATH" 2>/dev/null && SAT_B_STATUS="non_compliant" || true
    grep -q "SAT_B.*COMPLIANT" "$REPORT_PATH" 2>/dev/null && ! grep -q "SAT_B.*NON_COMPLIANT" "$REPORT_PATH" 2>/dev/null && SAT_B_STATUS="compliant" || true
    grep -q "SAT_C.*NON_COMPLIANT\|NON_COMPLIANT.*SAT_C" "$REPORT_PATH" 2>/dev/null && SAT_C_STATUS="non_compliant" || true
    grep -q "SAT_C.*COMPLIANT" "$REPORT_PATH" 2>/dev/null && ! grep -q "SAT_C.*NON_COMPLIANT" "$REPORT_PATH" 2>/dev/null && SAT_C_STATUS="compliant" || true
    grep -q "SAT_D.*NON_COMPLIANT\|NON_COMPLIANT.*SAT_D" "$REPORT_PATH" 2>/dev/null && SAT_D_STATUS="non_compliant" || true
    grep -q "SAT_D.*COMPLIANT" "$REPORT_PATH" 2>/dev/null && ! grep -q "SAT_D.*NON_COMPLIANT" "$REPORT_PATH" 2>/dev/null && SAT_D_STATUS="compliant" || true
    grep -q "SAT_E.*NON_COMPLIANT\|NON_COMPLIANT.*SAT_E" "$REPORT_PATH" 2>/dev/null && SAT_E_STATUS="non_compliant" || true
    grep -q "SAT_E.*COMPLIANT" "$REPORT_PATH" 2>/dev/null && ! grep -q "SAT_E.*NON_COMPLIANT" "$REPORT_PATH" 2>/dev/null && SAT_E_STATUS="compliant" || true

    REPORT_FIELD_COUNT=$(grep -c "SAT_[A-E]:" "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# Count how many satellites are in the GMAT script
SAT_COUNT_IN_SCRIPT=0
if [ -f "$SCRIPT_PATH" ]; then
    SAT_COUNT_IN_SCRIPT=$(grep -c "Create Spacecraft\|Create spacecraft" "$SCRIPT_PATH" 2>/dev/null || echo "0")
fi

# Check manifest was read
MANIFEST_EXISTS="false"
[ -f "/home/ga/Desktop/debris_manifest.csv" ] && MANIFEST_EXISTS="true"

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
    "manifest_exists": $MANIFEST_EXISTS,
    "satellite_count_in_script": $SAT_COUNT_IN_SCRIPT,
    "report_satellite_count": $REPORT_FIELD_COUNT,
    "compliant_count": $COMPLIANT_COUNT,
    "noncompliant_count": $NONCOMPLIANT_COUNT,
    "sat_a_status": "$SAT_A_STATUS",
    "sat_b_status": "$SAT_B_STATUS",
    "sat_c_status": "$SAT_C_STATUS",
    "sat_d_status": "$SAT_D_STATUS",
    "sat_e_status": "$SAT_E_STATUS",
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
