#!/bin/bash
echo "=== Exporting clinical_app_tour result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

OPENICE_RUNNING="false"
is_openice_running && OPENICE_RUNNING="true"

# Device created
DEVICE_CREATED=0
echo "$NEW_LOG" | grep -qiE "multiparameter|multiParam|device.*adapt|adapter.*start" && DEVICE_CREATED=1
[ $WINDOW_INCREASE -gt 0 ] && DEVICE_CREATED=1

# Each of the 4 clinical apps - use procedure vocabulary
# Vital Signs app: distinct from general "vital" log entries - look for app class name or specific launch
VITAL_SIGNS_APP=0
echo "$NEW_LOG" | grep -qiE "VitalSigns|vital.?sign.*app|vital.?sign.*launch|vital.?sign.*open" && VITAL_SIGNS_APP=1

# Xray Viewer app
XRAY_APP=0
echo "$NEW_LOG" | grep -qiE "XrayViewer|xray|x.?ray.*view|xray.*app|xray.*launch" && XRAY_APP=1

# Patient ID app
PATIENT_ID_APP=0
echo "$NEW_LOG" | grep -qiE "PatientId|patient.?id.*app|patient.*id.*launch|PatientContext" && PATIENT_ID_APP=1

# Infusion Safety app
INFUSION_SAFETY_APP=0
echo "$NEW_LOG" | grep -qiE "InfusionSafety|infusion.?safety.*app|infusion.*safety.*launch|safety.*infusion" && INFUSION_SAFETY_APP=1

APPS_LAUNCHED=$((VITAL_SIGNS_APP + XRAY_APP + PATIENT_ID_APP + INFUSION_SAFETY_APP))

# Guide file
GUIDE_FILE="/home/ga/Desktop/clinical_guide.txt"
GUIDE_EXISTS=0
GUIDE_SIZE=0
GUIDE_MTIME=0
GUIDE_HAS_VITAL=0
GUIDE_HAS_XRAY=0
GUIDE_HAS_PATIENT=0
GUIDE_HAS_INFUSION=0
GUIDE_HAS_CLINICAL_CONTENT=0

if [ -f "$GUIDE_FILE" ]; then
    GUIDE_EXISTS=1
    GUIDE_SIZE=$(stat -c %s "$GUIDE_FILE" 2>/dev/null || echo "0")
    GUIDE_MTIME=$(stat -c %Y "$GUIDE_FILE" 2>/dev/null || echo "0")
    grep -qiE "vital.?sign" "$GUIDE_FILE" 2>/dev/null && GUIDE_HAS_VITAL=1
    grep -qiE "x.?ray|xray" "$GUIDE_FILE" 2>/dev/null && GUIDE_HAS_XRAY=1
    grep -qiE "patient.?id|patient.*identif" "$GUIDE_FILE" 2>/dev/null && GUIDE_HAS_PATIENT=1
    grep -qiE "infusion.?safety|infusion.*pump|safety.*interlock|safety.*infusion" "$GUIDE_FILE" 2>/dev/null && GUIDE_HAS_INFUSION=1
    grep -qiE "interoperab|clinical|patient.*safety|ICU|critical.*care|device.*integrat" "$GUIDE_FILE" 2>/dev/null && GUIDE_HAS_CLINICAL_CONTENT=1
fi

cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_window_count": $INITIAL_WINDOWS,
    "final_window_count": $FINAL_WINDOWS,
    "window_increase": $WINDOW_INCREASE,
    "openice_running": $OPENICE_RUNNING,
    "device_created": $DEVICE_CREATED,
    "vital_signs_app": $VITAL_SIGNS_APP,
    "xray_app": $XRAY_APP,
    "patient_id_app": $PATIENT_ID_APP,
    "infusion_safety_app": $INFUSION_SAFETY_APP,
    "apps_launched": $APPS_LAUNCHED,
    "guide_exists": $GUIDE_EXISTS,
    "guide_size": $GUIDE_SIZE,
    "guide_mtime": $GUIDE_MTIME,
    "guide_has_vital": $GUIDE_HAS_VITAL,
    "guide_has_xray": $GUIDE_HAS_XRAY,
    "guide_has_patient": $GUIDE_HAS_PATIENT,
    "guide_has_infusion": $GUIDE_HAS_INFUSION,
    "guide_has_clinical_content": $GUIDE_HAS_CLINICAL_CONTENT
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
echo "Device: $DEVICE_CREATED | Apps: $APPS_LAUNCHED (VS=$VITAL_SIGNS_APP XR=$XRAY_APP PID=$PATIENT_ID_APP IS=$INFUSION_SAFETY_APP)"
echo "Guide: exists=$GUIDE_EXISTS size=$GUIDE_SIZE"
cat /tmp/task_result.json
