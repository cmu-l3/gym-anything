#!/bin/bash
echo "=== Exporting set_economical_route results ==="

PACKAGE="com.sygic.aura"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
echo "Capturing final screenshot..."
adb shell screencap -p /sdcard/task_final.png
adb pull /sdcard/task_final.png /tmp/task_final.png 2>/dev/null || true

# 2. Extract Preferences (The Evidence)
# We need to read the shared preferences to verify the setting.
# We try 'run-as' which works on debuggable builds, or standard root if available.
echo "Extracting preferences..."

PREFS_CONTENT=""
PREFS_MODIFIED="false"
FOUND_ECONOMICAL="false"

# Create a temp file for the pulled XMLs
mkdir -p /tmp/sygic_prefs
adb shell "run-as $PACKAGE cat /data/data/$PACKAGE/shared_prefs/*.xml" > /tmp/sygic_prefs/all_prefs.xml 2>/dev/null || true

# If run-as failed, try direct root access (if emulator is rooted)
if [ ! -s /tmp/sygic_prefs/all_prefs.xml ]; then
    adb shell "su root cat /data/data/$PACKAGE/shared_prefs/*.xml" > /tmp/sygic_prefs/all_prefs.xml 2>/dev/null || true
fi

# Analyze the prefs
if [ -s /tmp/sygic_prefs/all_prefs.xml ]; then
    PREFS_CONTENT=$(cat /tmp/sygic_prefs/all_prefs.xml)
    
    # Check for keywords indicating Economical route
    # Sygic often uses "computing" or "routing" keys. Values might be integers (e.g. 2) or strings.
    # Common mapping: 0=Fastest, 1=Shortest, 2=Economical (or similar)
    # Or strings like "economic", "eco"
    
    if echo "$PREFS_CONTENT" | grep -iE "route.*compute|planning|routing" | grep -iE "econom|eco|2"; then
        FOUND_ECONOMICAL="true"
    fi
    
    # Check file modification time (anti-gaming)
    # We check if the file on device was modified after TASK_START
    # Get epoch time of the prefs directory/files
    FILE_TIMESTAMP=$(adb shell "run-as $PACKAGE stat -c %Y /data/data/$PACKAGE/shared_prefs/*.xml" 2>/dev/null | sort -nr | head -1 || echo "0")
    if [ "$FILE_TIMESTAMP" -gt "$TASK_START" ]; then
        PREFS_MODIFIED="true"
    fi
fi

# 3. Check if App is Running
APP_RUNNING="false"
if adb shell pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "prefs_modified_during_task": $PREFS_MODIFIED,
    "found_economical_setting": $FOUND_ECONOMICAL,
    "prefs_content_snippet": "$(echo "$PREFS_CONTENT" | grep -iE "route|eco" | head -c 200 | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="