#!/system/bin/sh
# Export script for remove_plan_waypoint task

echo "=== Exporting results ==="

# 1. Take final screenshot
screencap -p /sdcard/task_final.png

# 2. Dump UI hierarchy (for text verification)
uiautomator dump /sdcard/window_dump.xml

# 3. Check for specific plan files (if accessible)
# Avare often stores state in shared_prefs or a database.
# We'll try to grep the shared preferences for the current destination/plan if possible.
# But root access might be needed to read /data/data directly.
# Since the agent runs as 'owner' (developer), we might have shell access.

PLAN_DATA=""
if [ -f /data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml ]; then
    # Try to copy prefs to sdcard for the verifier to read
    cp /data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml /sdcard/avare_prefs.xml
    chmod 666 /sdcard/avare_prefs.xml
fi

# 4. Create a JSON summary of the file state
# We can't easily parse XML in shell on Android easily, so we leave parsing to the python verifier.
# We just ensure the files are available.

echo "Files saved to /sdcard/:"
ls -l /sdcard/task_final.png /sdcard/window_dump.xml /sdcard/avare_prefs.xml 2>/dev/null

echo "=== Export complete ==="