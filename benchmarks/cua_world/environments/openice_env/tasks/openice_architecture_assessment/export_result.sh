#!/bin/bash
set -e
echo "=== Exporting OpenICE Architecture Assessment results ==="

source /workspace/scripts/task_utils.sh

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# --- 1. Report File Analysis ---
REPORT_PATH="/home/ga/Desktop/openice_architecture_assessment.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content for grep analysis (capped at 10KB to avoid issues)
    REPORT_CONTENT=$(head -c 10000 "$REPORT_PATH" 2>/dev/null || echo "")
fi

# Analyze report content for required sections
# Source module references
MODULE_HITS=0
for term in "interop-lab" "demo-apps" "demo-devices" "common" "mdpnp" "devices" "data-types"; do
    if echo "$REPORT_CONTENT" | grep -qi "$term"; then
        MODULE_HITS=$((MODULE_HITS + 1))
    fi
done

# Device type references
DEVICE_TYPE_HITS=0
DEVICE_TYPES_FOUND=""
for term in "Multiparameter" "Pulse Oximeter" "Pulse.Ox" "NIBP" "Noninvasive Blood Pressure" "InfusionPump" "Infusion Pump" "Capnograph" "CO2" "ECG" "IBP" "Invasive Blood Pressure" "Temperature"; do
    if echo "$REPORT_CONTENT" | grep -qi "$term"; then
        DEVICE_TYPE_HITS=$((DEVICE_TYPE_HITS + 1))
        DEVICE_TYPES_FOUND="${DEVICE_TYPES_FOUND}${term},"
    fi
done

# Clinical app references
APP_HITS=0
for term in "Vital Signs" "Infusion Safety" "Patient Assessment" "Device List" "Clinical App"; do
    if echo "$REPORT_CONTENT" | grep -qi "$term"; then
        APP_HITS=$((APP_HITS + 1))
    fi
done

# Technology stack references
TECH_HITS=0
for term in "Java" "Gradle" "JavaFX" "DDS" "Data Distribution" "ICE"; do
    if echo "$REPORT_CONTENT" | grep -qi "$term"; then
        TECH_HITS=$((TECH_HITS + 1))
    fi
done

# Recommendation presence
HAS_RECOMMENDATION="false"
for term in "recommend" "suitable" "assessment" "deployment" "evaluation" "conclusion" "feasib" "adopt"; do
    if echo "$REPORT_CONTENT" | grep -qi "$term"; then
        HAS_RECOMMENDATION="true"
        break
    fi
done

# --- 2. Log Analysis (Functional Verification) ---
# We analyze ONLY log lines written AFTER task start to verify actual agent actions
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG_LINES=""

if [ -f "$LOG_FILE" ]; then
    CURRENT_LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_LOG_SIZE" -gt "$INITIAL_LOG_SIZE" ]; then
        # Extract new lines
        NEW_LOG_LINES=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")
    fi
fi

# Count distinct device creation events in NEW logs
LOG_DEVICE_COUNT=0
LOG_DEVICES_FOUND=""
# Patterns match internal class names or log messages for creation
for term in "Multiparameter" "PulseOx" "Pulse.Oximeter" "NIBP" "InfusionPump" "Capnograph" "ECG" "IBP" "Temperature" "SimulatedDevice" "DeviceAdapter"; do
    if echo "$NEW_LOG_LINES" | grep -qi "$term"; then
        LOG_DEVICE_COUNT=$((LOG_DEVICE_COUNT + 1))
        LOG_DEVICES_FOUND="${LOG_DEVICES_FOUND}${term},"
    fi
done

# Check for clinical app launch in NEW logs
LOG_APP_LAUNCHED="false"
for term in "VitalSign" "Vital.Sign" "InfusionSafety" "Infusion.Safety" "PatientAssessment" "ClinicalApp" "AppType"; do
    if echo "$NEW_LOG_LINES" | grep -qi "$term"; then
        LOG_APP_LAUNCHED="true"
        break
    fi
done

# --- 3. Window State Analysis (Backup functional verification) ---
DISPLAY=:1 wmctrl -l 2>/dev/null > /tmp/final_windows.txt || true
FINAL_WINDOW_COUNT=$(wc -l < /tmp/final_windows.txt)
INITIAL_WINDOW_COUNT=$(cat /tmp/initial_window_count.txt 2>/dev/null || echo "0")
WINDOW_INCREASE=$((FINAL_WINDOW_COUNT - INITIAL_WINDOW_COUNT))

# Scan window titles for device names
WIN_DEVICE_COUNT=0
WIN_APP_FOUND="false"
while IFS= read -r line; do
    # Get window title part
    title=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}')
    for term in "Multiparameter" "PulseOx" "Pulse Ox" "NIBP" "Infusion" "Capnograph" "ECG" "IBP" "Temperature" "Monitor" "Simulated"; do
        if echo "$title" | grep -qi "$term"; then
            WIN_DEVICE_COUNT=$((WIN_DEVICE_COUNT + 1))
            break
        fi
    done
    for term in "Vital" "Safety" "Assessment" "Clinical"; do
        if echo "$title" | grep -qi "$term"; then
            WIN_APP_FOUND="true"
            break
        fi
    done
done < /tmp/final_windows.txt

# Calculate combined signals
# We take the max of log signals or window signals to be robust
TOTAL_DEVICE_SIGNALS=$(( LOG_DEVICE_COUNT > WIN_DEVICE_COUNT ? LOG_DEVICE_COUNT : WIN_DEVICE_COUNT ))
APP_DETECTED="false"
if [ "$LOG_APP_LAUNCHED" = "true" ] || [ "$WIN_APP_FOUND" = "true" ]; then
    APP_DETECTED="true"
fi

# Check OpenICE status
APP_RUNNING="false"
if is_openice_running; then
    APP_RUNNING="true"
fi

# --- 4. Final Screenshot ---
take_screenshot /tmp/task_final_state.png

# --- 5. Export JSON ---
# Create temp JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "app_running": $APP_RUNNING,
    "report": {
        "exists": $REPORT_EXISTS,
        "size_bytes": $REPORT_SIZE,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "module_references": $MODULE_HITS,
        "device_type_references": $DEVICE_TYPE_HITS,
        "device_types_found_str": "$DEVICE_TYPES_FOUND",
        "clinical_app_references": $APP_HITS,
        "tech_stack_references": $TECH_HITS,
        "has_recommendation": $HAS_RECOMMENDATION
    },
    "functional": {
        "log_device_count": $LOG_DEVICE_COUNT,
        "log_app_launched": $LOG_APP_LAUNCHED,
        "win_device_count": $WIN_DEVICE_COUNT,
        "win_app_found": $WIN_APP_FOUND,
        "total_device_signals": $TOTAL_DEVICE_SIGNALS,
        "app_detected": $APP_DETECTED,
        "window_increase": $WINDOW_INCREASE
    },
    "screenshot_path": "/tmp/task_final_state.png"
}
ENDJSON

# Safely move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json