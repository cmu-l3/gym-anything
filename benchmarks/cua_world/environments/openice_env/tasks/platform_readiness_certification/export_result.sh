#!/bin/bash
set -e
echo "=== Exporting platform_readiness_certification results ==="

export DISPLAY=:1

# Load timestamps and baselines
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size_post_setup.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/Desktop/platform_readiness_report.txt"
OPENICE_LOG="/home/ga/openice/logs/openice.log"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# ---------------------------------------------------------
# 1. GROUND TRUTH COLLECTION (System Investigation)
# ---------------------------------------------------------

# Java Version
JAVA_FULL=$(java -version 2>&1 | head -1)
# Extract just the version number (e.g., "17.0.1")
JAVA_VER=$(echo "$JAVA_FULL" | grep -oP 'version "\K[^"]+' || echo "unknown")

# Gradle Version
cd /opt/openice/mdpnp
GRADLE_VER=$(./gradlew --version 2>&1 | grep -i "^Gradle " | awk '{print $2}' || echo "unknown")

# DDS Implementation (Scan build.gradle files)
# Common keywords: rti, connext, opendds, opensplice, vortex
DDS_IMPL=""
if grep -rQi "rti" /opt/openice/mdpnp/*.gradle; then
    DDS_IMPL="RTI Connext"
elif grep -rQi "opendds" /opt/openice/mdpnp/*.gradle; then
    DDS_IMPL="OpenDDS"
elif grep -rQi "opensplice" /opt/openice/mdpnp/*.gradle; then
    DDS_IMPL="Vortex OpenSplice"
else
    # Fallback: check dependencies
    DDS_IMPL=$(grep -rEi "compile.*dds" /opt/openice/mdpnp/*.gradle | head -1 || echo "Unknown/Default")
fi

# Build Status
BUILD_DIR="/opt/openice/mdpnp/interop-lab/demo-apps/build/classes"
if [ -d "$BUILD_DIR" ]; then
    BUILD_EXISTS=true
else
    BUILD_EXISTS=false
fi

# Log File Existence
if [ -f "$OPENICE_LOG" ] && [ -s "$OPENICE_LOG" ]; then
    LOG_VALID=true
else
    LOG_VALID=false
fi

# ---------------------------------------------------------
# 2. ACTIVITY DETECTION (Log & Window Analysis)
# ---------------------------------------------------------

# Log Analysis (New lines only)
NEW_LOG_CONTENT=""
if [ -f "$OPENICE_LOG" ]; then
    NEW_LOG_CONTENT=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$OPENICE_LOG" 2>/dev/null || echo "")
fi

# Device Creation in Logs
DEVICE_IN_LOGS=false
if echo "$NEW_LOG_CONTENT" | grep -qiE "multiparameter|monitor|ecg|pulse|oximeter|infusion|pump|simulated"; then
    DEVICE_IN_LOGS=true
fi

# App Launch in Logs
APP_IN_LOGS=false
if echo "$NEW_LOG_CONTENT" | grep -qiE "vital|sign|infusion|safety|app.*start|launch|demo"; then
    APP_IN_LOGS=true
fi

# Window Analysis
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
INITIAL_WINDOWS=$(cat /tmp/initial_windows_post_setup.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(echo "$INITIAL_WINDOWS" | wc -l)
FINAL_COUNT=$(echo "$FINAL_WINDOWS" | wc -l)
WINDOW_INCREASE=$((FINAL_COUNT - INITIAL_COUNT))

# Check for specific window titles
DEVICE_WINDOW=false
if echo "$FINAL_WINDOWS" | grep -qiE "multiparameter|monitor|simulated|device"; then
    DEVICE_WINDOW=true
fi

APP_WINDOW=false
if echo "$FINAL_WINDOWS" | grep -qiE "vital|sign|infusion|safety|demo"; then
    APP_WINDOW=true
fi

# ---------------------------------------------------------
# 3. REPORT ANALYSIS
# ---------------------------------------------------------

REPORT_EXISTS=false
REPORT_SIZE=0
REPORT_CONTENT=""
REPORT_AFTER_START=false

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE")
    REPORT_CONTENT=$(cat "$REPORT_FILE")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_AFTER_START=true
    fi
fi

# ---------------------------------------------------------
# 4. JSON EXPORT
# ---------------------------------------------------------

# Create JSON securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "ground_truth": {
    "java_version": "$JAVA_VER",
    "gradle_version": "$GRADLE_VER",
    "dds_impl": "$DDS_IMPL",
    "build_exists": $BUILD_EXISTS,
    "log_valid": $LOG_VALID
  },
  "activity": {
    "device_in_logs": $DEVICE_IN_LOGS,
    "app_in_logs": $APP_IN_LOGS,
    "window_increase": $WINDOW_INCREASE,
    "device_window_visible": $DEVICE_WINDOW,
    "app_window_visible": $APP_WINDOW
  },
  "report": {
    "exists": $REPORT_EXISTS,
    "size": $REPORT_SIZE,
    "created_during_task": $REPORT_AFTER_START,
    "content_preview": $(echo "$REPORT_CONTENT" | head -n 20 | jq -R -s '.')
  }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json