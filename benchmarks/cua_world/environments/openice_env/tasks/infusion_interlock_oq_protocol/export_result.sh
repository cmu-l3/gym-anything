#!/bin/bash
echo "=== Exporting infusion_interlock_oq_protocol result ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# Final screenshot (framework requirement)
# ---------------------------------------------------------------
take_screenshot /tmp/task_final_screenshot.png

# ---------------------------------------------------------------
# Timestamps
# ---------------------------------------------------------------
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ---------------------------------------------------------------
# Window analysis
# ---------------------------------------------------------------
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_DELTA=$((FINAL_WINDOWS - INITIAL_WINDOWS))
CURRENT_WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null | sed 's/"/\\"/g' | tr '\n' '|')

# ---------------------------------------------------------------
# OpenICE process status
# ---------------------------------------------------------------
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# ---------------------------------------------------------------
# Log analysis: only new lines since task start
# ---------------------------------------------------------------
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Pulse Oximeter creation
PULSE_OX_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Pulse.*Ox|SpO2.*adapt|SimPulseOx|Nonin|Masimo"; then
    PULSE_OX_CREATED="true"
fi

# Infusion Pump creation
PUMP_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Infusion.*Pump|Pump.*Sim|SimInfusion|Alaris|QCore"; then
    PUMP_CREATED="true"
fi

# Infusion Safety app launch
SAFETY_APP_LAUNCHED="false"
if echo "$NEW_LOG" | grep -qiE "Infusion.*Safety|Safety.*Interlock|PCA|Objective.*Safety"; then
    SAFETY_APP_LAUNCHED="true"
fi
# Also check window titles as backup
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Infusion.*Safety|Safety"; then
    SAFETY_APP_LAUNCHED="true"
fi

# Extract device UUIDs from new log entries
DEVICE_UUIDS=$(echo "$NEW_LOG" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | sort -u | tr '\n' '|')

# ---------------------------------------------------------------
# Artifact checks: screenshots
# ---------------------------------------------------------------
THRESHOLD_PNG_EXISTS="false"
THRESHOLD_PNG_MTIME=0
if [ -f "/home/ga/Desktop/oq_test_threshold.png" ]; then
    THRESHOLD_PNG_EXISTS="true"
    THRESHOLD_PNG_MTIME=$(stat -c %Y "/home/ga/Desktop/oq_test_threshold.png" 2>/dev/null || echo "0")
fi

FAILSAFE_PNG_EXISTS="false"
FAILSAFE_PNG_MTIME=0
if [ -f "/home/ga/Desktop/oq_test_failsafe.png" ]; then
    FAILSAFE_PNG_EXISTS="true"
    FAILSAFE_PNG_MTIME=$(stat -c %Y "/home/ga/Desktop/oq_test_failsafe.png" 2>/dev/null || echo "0")
fi

# ---------------------------------------------------------------
# Artifact checks: CSV
# ---------------------------------------------------------------
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
CSV_SIZE=0
CSV_CONTENT=""
if [ -f "/home/ga/Desktop/oq_test_results.csv" ]; then
    CSV_EXISTS="true"
    CSV_ROWS=$(wc -l < "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null || echo "0")
    CSV_SIZE=$(stat -c %s "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null || echo "0")
    CSV_CONTENT=$(cat "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
fi

# Check for specific test names in CSV
CSV_HAS_THRESHOLD="false"
CSV_HAS_HYSTERESIS="false"
CSV_HAS_FAILSAFE="false"
CSV_HAS_BOUNDARY="false"
if [ "$CSV_EXISTS" = "true" ]; then
    grep -qiE "threshold|test.?1" "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null && CSV_HAS_THRESHOLD="true"
    grep -qiE "hysteresis|recovery|test.?2" "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null && CSV_HAS_HYSTERESIS="true"
    grep -qiE "fail.?safe|sensor|disconnect|test.?3" "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null && CSV_HAS_FAILSAFE="true"
    grep -qiE "boundary|exact|test.?4" "/home/ga/Desktop/oq_test_results.csv" 2>/dev/null && CSV_HAS_BOUNDARY="true"
fi

# ---------------------------------------------------------------
# Artifact checks: validation report
# ---------------------------------------------------------------
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_HAS_UDI="false"
REPORT_HAS_OQ_DETERMINATION="false"
REPORT_HAS_HYSTERESIS="false"
REPORT_HAS_ALL_TESTS="false"
if [ -f "/home/ga/Desktop/oq_validation_report.txt" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "/home/ga/Desktop/oq_validation_report.txt" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "/home/ga/Desktop/oq_validation_report.txt" 2>/dev/null || echo "0")

    REPORT_CONTENT=$(cat "/home/ga/Desktop/oq_validation_report.txt" 2>/dev/null)

    # Check for UDI/UUID references
    if echo "$REPORT_CONTENT" | grep -qiE '[0-9a-f]{8}-[0-9a-f]{4}|UDI|UUID|device.*identifier'; then
        REPORT_HAS_UDI="true"
    fi

    # Check for OQ determination
    if echo "$REPORT_CONTENT" | grep -qiE 'PASS|FAIL|determination|qualification'; then
        REPORT_HAS_OQ_DETERMINATION="true"
    fi

    # Check for hysteresis finding
    if echo "$REPORT_CONTENT" | grep -qiE 'hysteresis|recovery.*point|recovery.*threshold'; then
        REPORT_HAS_HYSTERESIS="true"
    fi

    # Check that all 4 tests are mentioned
    T1=$(echo "$REPORT_CONTENT" | grep -ciE 'threshold.*response|test.?1')
    T2=$(echo "$REPORT_CONTENT" | grep -ciE 'hysteresis|recovery|test.?2')
    T3=$(echo "$REPORT_CONTENT" | grep -ciE 'fail.?safe|sensor.*fail|disconnect|test.?3')
    T4=$(echo "$REPORT_CONTENT" | grep -ciE 'boundary|test.?4')
    if [ "$T1" -gt 0 ] && [ "$T2" -gt 0 ] && [ "$T3" -gt 0 ] && [ "$T4" -gt 0 ]; then
        REPORT_HAS_ALL_TESTS="true"
    fi
fi

# ---------------------------------------------------------------
# Pulse Ox window state (for fail-safe verification)
# After Test 3, the Pulse Ox window should have been closed at some point
# ---------------------------------------------------------------
PULSE_OX_WINDOW_OPEN="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Pulse.*Ox|SpO2"; then
    PULSE_OX_WINDOW_OPEN="true"
fi

PUMP_WINDOW_OPEN="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Infusion.*Pump|Pump"; then
    PUMP_WINDOW_OPEN="true"
fi

SAFETY_APP_WINDOW_OPEN="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Infusion.*Safety|Safety"; then
    SAFETY_APP_WINDOW_OPEN="true"
fi

# ---------------------------------------------------------------
# Write result JSON
# ---------------------------------------------------------------
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "window_delta": $WINDOW_DELTA,
    "current_windows": "$CURRENT_WINDOW_LIST",
    "openice_running": $OPENICE_RUNNING,
    "logs": {
        "pulse_ox_created": $PULSE_OX_CREATED,
        "pump_created": $PUMP_CREATED,
        "safety_app_launched": $SAFETY_APP_LAUNCHED,
        "device_uuids": "$DEVICE_UUIDS"
    },
    "window_state": {
        "pulse_ox_window_open": $PULSE_OX_WINDOW_OPEN,
        "pump_window_open": $PUMP_WINDOW_OPEN,
        "safety_app_window_open": $SAFETY_APP_WINDOW_OPEN
    },
    "artifacts": {
        "threshold_png_exists": $THRESHOLD_PNG_EXISTS,
        "threshold_png_mtime": $THRESHOLD_PNG_MTIME,
        "failsafe_png_exists": $FAILSAFE_PNG_EXISTS,
        "failsafe_png_mtime": $FAILSAFE_PNG_MTIME,
        "csv_exists": $CSV_EXISTS,
        "csv_rows": $CSV_ROWS,
        "csv_mtime": $CSV_MTIME,
        "csv_size": $CSV_SIZE,
        "csv_content": "$CSV_CONTENT",
        "csv_has_threshold": $CSV_HAS_THRESHOLD,
        "csv_has_hysteresis": $CSV_HAS_HYSTERESIS,
        "csv_has_failsafe": $CSV_HAS_FAILSAFE,
        "csv_has_boundary": $CSV_HAS_BOUNDARY,
        "report_exists": $REPORT_EXISTS,
        "report_size": $REPORT_SIZE,
        "report_mtime": $REPORT_MTIME,
        "report_has_udi": $REPORT_HAS_UDI,
        "report_has_oq_determination": $REPORT_HAS_OQ_DETERMINATION,
        "report_has_hysteresis": $REPORT_HAS_HYSTERESIS,
        "report_has_all_tests": $REPORT_HAS_ALL_TESTS
    }
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json
