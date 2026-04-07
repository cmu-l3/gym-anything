#!/system/bin/sh
echo "=== Exporting disable_auto_zoom results ==="

# Capture final screenshot for VLM verification
screencap -p /sdcard/final_screenshot.png

# Capture UI hierarchy
uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1

# Export Shared Preferences for programmatic verification
# We copy it to /sdcard/ so it can be pulled by the host verifier
PREFS_SRC="/data/data/com.sygic.aura/shared_prefs/com.sygic.aura_preferences.xml"
PREFS_DST="/sdcard/sygic_prefs_dump.xml"

# Try to copy using su (required for /data/data access)
if which su >/dev/null; then
    su -c "cp $PREFS_SRC $PREFS_DST"
    su -c "chmod 666 $PREFS_DST"
else
    # Fallback: try run-as if debuggable (unlikely for store apps but possible in dev env)
    run-as com.sygic.aura cp shared_prefs/com.sygic.aura_preferences.xml $PREFS_DST 2>/dev/null
fi

# Create a simple JSON result file with timestamp
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PREFS_EXISTS="false"
[ -f "$PREFS_DST" ] && PREFS_EXISTS="true"

echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"prefs_exported\": $PREFS_EXISTS," >> /sdcard/task_result.json
echo "  \"final_screenshot_path\": \"/sdcard/final_screenshot.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "=== Export complete ==="