#!/system/bin/sh
# Export script for configure_traffic_alert_thresholds
# Runs on the Android device

echo "=== Exporting Task Results ==="

PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
EXPORT_DIR="/sdcard"
RESULT_JSON="$EXPORT_DIR/task_result.json"

# 1. Capture final screenshot
screencap -p "$EXPORT_DIR/task_final.png"

# 2. Check if preferences file exists and copy it
# We need root access to read /data/data usually, assuming shell has it or su is available
if su root ls "$PREFS_FILE" >/dev/null 2>&1; then
    echo "Preferences file found."
    # Copy to sdcard so we can read it easily
    su root cp "$PREFS_FILE" "$EXPORT_DIR/prefs_dump.xml"
    chmod 666 "$EXPORT_DIR/prefs_dump.xml"
    PREFS_EXISTS="true"
else
    echo "Preferences file NOT found at $PREFS_FILE"
    PREFS_EXISTS="false"
fi

# 3. Get file modification time if possible (stat might differ on Android versions)
# We'll use a simple approach: if we copied it, we have it.
# Anti-gaming is handled by comparing values against defaults/requirements.

# 4. Check if app is running
if pidof "$PACKAGE" >/dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 5. Create JSON result
# Note: formatting JSON in shell is fragile, keeping it simple
echo "{" > "$RESULT_JSON"
echo "  \"prefs_exists\": $PREFS_EXISTS," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "=== Export Complete ==="