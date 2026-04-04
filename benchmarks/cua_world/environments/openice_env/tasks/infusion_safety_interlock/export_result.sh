#!/bin/bash
echo "=== Exporting infusion_safety_interlock result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Window counts
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Get ONLY new log lines since task start
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# Check OpenICE running
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Detect monitoring device creation (Multiparameter Monitor = SpO2 source)
# Check new log AND window titles for monitor-type device
MONITOR_DEVICE_CREATED=0
if echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|vital.*monitor|monitor.*vital|SpO2.*adapt|adapt.*SpO2"; then
    MONITOR_DEVICE_CREATED=1
fi
# Also check window titles for device adapter windows
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "multiparameter|vital.*monitor"; then
    MONITOR_DEVICE_CREATED=1
fi

# Detect infusion pump device creation
INFUSION_PUMP_CREATED=0
if echo "$NEW_LOG" | grep -qiE "infusion.?pump|pump.*adapter|pump.*device|InfusionPump|PumpSim|pump.*simul"; then
    INFUSION_PUMP_CREATED=1
fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "infusion.?pump|pump.*adapter"; then
    INFUSION_PUMP_CREATED=1
fi

# Detect Infusion Safety app launch
INFUSION_SAFETY_LAUNCHED=0
if echo "$NEW_LOG" | grep -qiE "infusion.?safety|InfusionSafety|safety.*app|safety.*launch|safety.*clinical"; then
    INFUSION_SAFETY_LAUNCHED=1
fi
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "infusion.?safety|safety.*app"; then
    INFUSION_SAFETY_LAUNCHED=1
fi

# Detect any device creation (broader check)
ANY_DEVICE_CREATED=0
if echo "$NEW_LOG" | grep -qiE "device.*adapt|adapt.*start|adapter.*created|ICE.*Device|device.*simul"; then
    ANY_DEVICE_CREATED=1
fi
if [ $WINDOW_INCREASE -gt 0 ]; then
    ANY_DEVICE_CREATED=1
fi

# Check report file
REPORT_FILE="/home/ga/Desktop/infusion_safety_config.txt"
REPORT_EXISTS=0
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_HAS_DEVICE_TYPES=0
REPORT_HAS_THRESHOLD=0
REPORT_HAS_BEHAVIOR=0
REPORT_HAS_SPO2=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=1
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")

    # Check content using grep -q (not grep -c || echo)
    grep -qiE "infusion.?pump|pump.*device|infusion.*delivery" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_DEVICE_TYPES=1
    grep -qiE "monitor|multiparameter|SpO2.*device|vital.*device" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_DEVICE_TYPES=$((REPORT_HAS_DEVICE_TYPES > 0 ? 1 : 0))

    # Check for SpO2 specifically
    grep -qiE "SpO2|spo2|oxygen.*satur|O2.*sat" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_SPO2=1

    # Check for threshold value
    grep -qiE "threshold|interlock|limit|[0-9][0-9]%" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_THRESHOLD=1

    # Check for behavior description
    grep -qiE "stop|pause|halt|alarm|alert|trigger|activat" "$REPORT_FILE" 2>/dev/null && REPORT_HAS_BEHAVIOR=1
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_window_count": $INITIAL_WINDOWS,
    "final_window_count": $FINAL_WINDOWS,
    "window_increase": $WINDOW_INCREASE,
    "openice_running": $OPENICE_RUNNING,
    "monitor_device_created": $MONITOR_DEVICE_CREATED,
    "infusion_pump_created": $INFUSION_PUMP_CREATED,
    "infusion_safety_launched": $INFUSION_SAFETY_LAUNCHED,
    "any_device_created": $ANY_DEVICE_CREATED,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_has_device_types": $REPORT_HAS_DEVICE_TYPES,
    "report_has_spo2": $REPORT_HAS_SPO2,
    "report_has_threshold": $REPORT_HAS_THRESHOLD,
    "report_has_behavior": $REPORT_HAS_BEHAVIOR
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
echo "Monitor device: $MONITOR_DEVICE_CREATED | Pump: $INFUSION_PUMP_CREATED | Safety app: $INFUSION_SAFETY_LAUNCHED"
echo "Report exists: $REPORT_EXISTS (size: $REPORT_SIZE)"
cat /tmp/task_result.json
