#!/system/bin/sh
# Export script for set_power_saving_always task

echo "=== Exporting results for set_power_saving_always ==="

TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
PACKAGE="com.sygic.aura"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Dump UI Hierarchy (for XML verification of text on screen)
uiautomator dump /sdcard/window_dump.xml 2>/dev/null

# 3. Attempt to extract internal preferences (Root/Debug access required)
# We look for shared_prefs containing power saving keys
mkdir -p /sdcard/task_evidence
PREFS_FOUND="false"

# Copy all shared_prefs to sdcard for analysis
if [ -d "/data/data/$PACKAGE/shared_prefs" ]; then
    cp -r "/data/data/$PACKAGE/shared_prefs/" "/sdcard/task_evidence/" 2>/dev/null
    chmod -R 777 /sdcard/task_evidence/
    PREFS_FOUND="true"
fi

# 4. Check if App is running
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
# We write this to a temp file then move it to ensure atomicity
cat > /sdcard/temp_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "prefs_extracted": $PREFS_FOUND,
    "screenshot_path": "/sdcard/task_final.png",
    "ui_dump_path": "/sdcard/window_dump.xml",
    "evidence_dir": "/sdcard/task_evidence"
}
EOF

mv /sdcard/temp_result.json /sdcard/task_result.json
chmod 666 /sdcard/task_result.json

echo "=== Export complete ==="