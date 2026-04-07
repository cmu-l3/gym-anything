#!/system/bin/sh
# Export script for configure_wb_profile task.

echo "=== Exporting Task Results ==="

# 1. Capture final screenshot (CRITICAL for VLM verification)
screencap -p /sdcard/final_screenshot.png
echo "Screenshot saved to /sdcard/final_screenshot.png"

# 2. Dump UI hierarchy (XML) as backup evidence
uiautomator dump /sdcard/ui_dump.xml
echo "UI dump saved to /sdcard/ui_dump.xml"

# 3. Attempt to retrieve internal W&B data if accessible
# Avare typically stores W&B in shared prefs or internal JSON.
# We try to copy shared prefs to sdcard for the verifier to read.
# Note: This requires root or debuggable APK. The environment usually runs as root or shell user.
# We use 'run-as' or direct copy if user is root.

TARGET_PREFS="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"
DEST_PREFS="/sdcard/avare_preferences.xml"

if [ -f "$TARGET_PREFS" ]; then
    cp "$TARGET_PREFS" "$DEST_PREFS"
    chmod 666 "$DEST_PREFS"
    echo "Preferences copied."
else
    echo "Could not access preferences file directly."
    # Try via cat if cp fails (permission issues)
    cat "$TARGET_PREFS" > "$DEST_PREFS" 2>/dev/null
fi

# 4. Create metadata JSON
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(pidof com.ds.avare > /dev/null && echo "true" || echo "false")

echo "{\"task_start\": $TASK_START, \"task_end\": $TASK_END, \"app_running\": $APP_RUNNING}" > /sdcard/task_metadata.json

echo "=== Export Complete ==="