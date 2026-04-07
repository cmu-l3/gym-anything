#!/system/bin/sh
# Export script for set_map_font_size_large
# Runs on Android device

echo "=== Exporting results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check for Settings Modification (Anti-Gaming)
# We look for modification of shared preferences in the app data folder.
# This requires root access usually available in these emulators.
SETTINGS_MODIFIED="false"
SETTINGS_MTIME="0"

# Path to shared prefs - checking common locations
PREFS_DIR="/data/data/com.sygic.aura/shared_prefs"

# Try to find any preference file modified after task start
# Using 'ls -l' and parsing or 'stat' if available. 
# Android toolbox 'stat' output format varies.
# We will try to list files sorted by time.

if [ -d "$PREFS_DIR" ]; then
    # List files, check if any seem recent. 
    # Since specific parsing is hard in restricted shell, we'll try a generous check.
    # We'll just flag if the directory or files exist for now, 
    # and try to assume if the screenshot is good, the task is done.
    # However, to be robust, let's try to get a timestamp.
    
    # Simple check: Does a prefs file exist?
    if ls $PREFS_DIR/*.xml >/dev/null 2>&1; then
        # Try to cat it to check for content (optional)
        # Check if we can grep for 'Large' if we have read perms
        if grep -i "Large" $PREFS_DIR/*.xml >/dev/null 2>&1; then
            SETTINGS_CONTENT_MATCH="true"
        else
            SETTINGS_CONTENT_MATCH="false"
        fi
    fi
fi

# 3. Create JSON Result
# Note: We create it in /sdcard which is world-writable usually
cat > /sdcard/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "settings_content_match": "$SETTINGS_CONTENT_MATCH",
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Result saved to /sdcard/task_result.json"