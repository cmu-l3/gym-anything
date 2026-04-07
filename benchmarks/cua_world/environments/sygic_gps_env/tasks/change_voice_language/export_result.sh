#!/system/bin/sh
echo "=== Exporting change_voice_language result ==="

PACKAGE="com.sygic.aura"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
screencap -p /sdcard/task_final.png

# Check if application preferences were modified during the task
# We check /data/data which requires root/su, but this script runs as shell/root in this env
PREFS_MODIFIED="false"
MODIFIED_COUNT=0

# Check shared_prefs (requires su)
if [ -d "/data/data/$PACKAGE/shared_prefs" ]; then
    # Find files modified after task start
    # Android find is limited, so we iterate and check timestamps if possible, 
    # or rely on simple 'ls -l' parsing if stat is unavailable.
    # Here we assume basic toolbox/toybox 'stat' or 'ls' is available.
    
    # Simple check: Listing files sorted by time
    RECENT_FILES=$(ls -lt /data/data/$PACKAGE/shared_prefs/ | head -n 3)
    echo "Recent prefs: $RECENT_FILES"
    
    # More robust check might be difficult in restricted shell, 
    # so we'll rely on the verifier to check the specific timestamp logic 
    # if we can export the file list with timestamps.
    ls -l --full-time /data/data/$PACKAGE/shared_prefs/ > /sdcard/prefs_list.txt 2>/dev/null || ls -l /data/data/$PACKAGE/shared_prefs/ > /sdcard/prefs_list.txt
    
    # We will simply flag true here if we detect *any* change, 
    # but the python verifier will do the heavy lifting.
    PREFS_MODIFIED="true" 
fi

# Check if app is in foreground
APP_RUNNING="false"
if dumpsys window | grep mCurrentFocus | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# Create result JSON
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"prefs_checked\": true" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# Copy prefs list to accessible location
cp /sdcard/prefs_list.txt /sdcard/task_prefs_list.txt 2>/dev/null || true

echo "=== Export complete ==="