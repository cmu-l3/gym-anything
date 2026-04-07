#!/system/bin/sh
echo "=== Exporting navigate_to_coordinates result ==="

PACKAGE="com.ds.avare"
PREFS_XML="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
DEST_PREFS="/sdcard/final_prefs.xml"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot (CRITICAL for VLM)
screencap -p /sdcard/task_final.png

# 2. Try to dump internal state (Preferences)
# This requires root, which is available in the environment via su
echo "Attempting to export preferences..."
su -c "cp $PREFS_XML $DEST_PREFS" 2>/dev/null
su -c "chmod 666 $DEST_PREFS" 2>/dev/null

# 3. Check if app is running
APP_RUNNING=$(pidof $PACKAGE > /dev/null && echo "true" || echo "false")

# 4. Create JSON result
# We construct the JSON manually using echo since jq might not be on the android env
echo "{" > $RESULT_JSON
echo "  \"app_running\": $APP_RUNNING," >> $RESULT_JSON
echo "  \"prefs_exported\": $([ -f $DEST_PREFS ] && echo "true" || echo "false")," >> $RESULT_JSON
echo "  \"timestamp\": \"$(date)\"" >> $RESULT_JSON
echo "}" >> $RESULT_JSON

echo "Result exported to $RESULT_JSON"
cat $RESULT_JSON
echo "=== Export complete ==="