#!/bin/bash
echo "=== Exporting Simulated Device Parameter Exploration Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# --- 1. Timestamp & Window State Analysis ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# --- 2. Log Analysis (New Activity Only) ---
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
# Get only the lines added during the task
NEW_LOG_CONTENT=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check for OpenICE running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Detect device creation in logs (looking for specific type keywords)
CREATED_MULTIPARAMETER=0
echo "$NEW_LOG_CONTENT" | grep -qiE "Multiparameter|MultiParam" && CREATED_MULTIPARAMETER=1

CREATED_CAPNOGRAPH=0
echo "$NEW_LOG_CONTENT" | grep -qiE "Capno|CO2|Respiratory" && CREATED_CAPNOGRAPH=1

CREATED_PULSEOX=0
echo "$NEW_LOG_CONTENT" | grep -qiE "PulseOx|SpO2|Oximeter" && CREATED_PULSEOX=1

CREATED_INFUSION=0
echo "$NEW_LOG_CONTENT" | grep -qiE "Infusion|Pump" && CREATED_INFUSION=1

CREATED_NIBP=0
echo "$NEW_LOG_CONTENT" | grep -qiE "NIBP|Blood.*Press|Non.*Invasive" && CREATED_NIBP=1

# Also check window titles for backup evidence (OpenICE creates windows named after devices)
CURRENT_WINDOW_TITLES=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
echo "$CURRENT_WINDOW_TITLES" | grep -qiE "Multiparameter" && CREATED_MULTIPARAMETER=1
echo "$CURRENT_WINDOW_TITLES" | grep -qiE "Capno|CO2" && CREATED_CAPNOGRAPH=1
echo "$CURRENT_WINDOW_TITLES" | grep -qiE "Pulse|SpO2" && CREATED_PULSEOX=1
echo "$CURRENT_WINDOW_TITLES" | grep -qiE "Infusion|Pump" && CREATED_INFUSION=1

# Count distinct types detected
DISTINCT_DEVICES_DETECTED=$((CREATED_MULTIPARAMETER + CREATED_CAPNOGRAPH + CREATED_PULSEOX + CREATED_INFUSION + CREATED_NIBP))

# --- 3. Report Content Analysis ---
REPORT_FILE="/home/ga/Desktop/device_parameter_catalog.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_VALID_TIMESTAMP=0
REPORT_CONTENT_SCORE=0
HAS_NUMERIC_WAVEFORM=0
HAS_SUMMARY=0
PARAM_COUNT=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID_TIMESTAMP=1
    fi

    # Check for required classification keywords
    if grep -q "Numeric" "$REPORT_FILE" && grep -q "Waveform" "$REPORT_FILE"; then
        HAS_NUMERIC_WAVEFORM=1
    fi

    # Check for Summary section
    if grep -qi "Summary" "$REPORT_FILE"; then
        HAS_SUMMARY=1
    fi

    # Count physiological parameters mentioned
    # We look for common ones: Heart Rate, SpO2, etCO2, RR, BP, ECG
    # Using grep -c on the file for each
    P1=$(grep -ci "Heart.*Rate" "$REPORT_FILE")
    P2=$(grep -ci "SpO2" "$REPORT_FILE")
    P3=$(grep -ciE "etCO2|CO2" "$REPORT_FILE")
    P4=$(grep -ciE "Resp.*Rate|RR" "$REPORT_FILE")
    P5=$(grep -ciE "Blood.*Press|BP|Sys|Dia" "$REPORT_FILE")
    P6=$(grep -ciE "ECG|EKG" "$REPORT_FILE")
    P7=$(grep -ciE "Pleth" "$REPORT_FILE")
    
    # Simple count of how many distinct parameter types were found
    [ $P1 -gt 0 ] && PARAM_COUNT=$((PARAM_COUNT + 1))
    [ $P2 -gt 0 ] && PARAM_COUNT=$((PARAM_COUNT + 1))
    [ $P3 -gt 0 ] && PARAM_COUNT=$((PARAM_COUNT + 1))
    [ $P4 -gt 0 ] && PARAM_COUNT=$((PARAM_COUNT + 1))
    [ $P5 -gt 0 ] && PARAM_COUNT=$((PARAM_COUNT + 1))
    [ $P6 -gt 0 ] && PARAM_COUNT=$((PARAM_COUNT + 1))
    [ $P7 -gt 0 ] && PARAM_COUNT=$((PARAM_COUNT + 1))

    # Check for device type headers (formatting structure)
    # Looking for lines starting with === or similar, or "Device Type:"
    STRUCTURE_SCORE=$(grep -cE "^===|^Device Type:" "$REPORT_FILE")
fi

# --- 4. Export JSON ---
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "initial_windows": $INITIAL_WINDOWS,
    "final_windows": $FINAL_WINDOWS,
    "window_increase": $WINDOW_INCREASE,
    "distinct_devices_detected": $DISTINCT_DEVICES_DETECTED,
    "device_details": {
        "multiparameter": $CREATED_MULTIPARAMETER,
        "capnograph": $CREATED_CAPNOGRAPH,
        "pulseox": $CREATED_PULSEOX,
        "infusion": $CREATED_INFUSION,
        "nibp": $CREATED_NIBP
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "valid_timestamp": $REPORT_VALID_TIMESTAMP,
        "has_classification": $HAS_NUMERIC_WAVEFORM,
        "has_summary": $HAS_SUMMARY,
        "distinct_params_found": $PARAM_COUNT,
        "structure_score": ${STRUCTURE_SCORE:-0}
    }
}
EOF

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
echo "Devices Detected: $DISTINCT_DEVICES_DETECTED"
echo "Window Increase: $WINDOW_INCREASE"
echo "Report Exists: $REPORT_EXISTS (Params found: $PARAM_COUNT)"
cat /tmp/task_result.json