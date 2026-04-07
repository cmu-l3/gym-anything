#!/system/bin/sh
echo "=== Exporting configure_speed_warnings results ==="

PACKAGE="com.sygic.aura"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
screencap -p /tmp/task_final.png 2>/dev/null || true

# 1. Check if app is running
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Analyze Preferences for Specific Settings
# We grep the XML files for keys related to our requirements.
# We are looking for:
# - Enabled speed warning
# - Tolerance of 10
# - Enabled camera/radar warning

SPEED_WARN_ENABLED="false"
TOLERANCE_SET="false"
CAMERA_WARN_ENABLED="false"
FILES_MODIFIED="false"

if [ -d "$PREFS_DIR" ]; then
    # Check modification times
    # Find files modified after task start
    MOD_COUNT=$(find "$PREFS_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$MOD_COUNT" -gt 0 ]; then
        FILES_MODIFIED="true"
    fi

    # Grep for Speed Warning (True)
    # Pattern matches various potential key names: speedLimit, speedWarn, etc.
    if grep -riE "speed.*warn.*true|warn.*speed.*true|speed.*limit.*true" "$PREFS_DIR" > /dev/null; then
        SPEED_WARN_ENABLED="true"
    fi

    # Grep for Tolerance (10)
    # Pattern looks for keys containing tolerance/threshold/offset and value 10
    # Note: value might be inside value="10" or just >10<
    if grep -riE "tolerance.*10|threshold.*10|offset.*10|over.*10" "$PREFS_DIR" > /dev/null; then
        TOLERANCE_SET="true"
    fi

    # Grep for Speed Camera/Radar (True)
    if grep -riE "camera.*true|radar.*true|speedcam.*true" "$PREFS_DIR" > /dev/null; then
        CAMERA_WARN_ENABLED="true"
    fi
fi

# 3. Create JSON Result
# We construct the JSON manually using echo since jq might not be on the device
echo "{" > "$RESULT_FILE"
echo "  \"task_start\": $TASK_START," >> "$RESULT_FILE"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_FILE"
echo "  \"files_modified_during_task\": $FILES_MODIFIED," >> "$RESULT_FILE"
echo "  \"settings_detected\": {" >> "$RESULT_FILE"
echo "    \"speed_warning_enabled\": $SPEED_WARN_ENABLED," >> "$RESULT_FILE"
echo "    \"tolerance_set_to_10\": $TOLERANCE_SET," >> "$RESULT_FILE"
echo "    \"camera_warning_enabled\": $CAMERA_WARN_ENABLED" >> "$RESULT_FILE"
echo "  }," >> "$RESULT_FILE"
echo "  \"screenshot_path\": \"/tmp/task_final.png\"" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

# Set permissions so we can copy it out
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="