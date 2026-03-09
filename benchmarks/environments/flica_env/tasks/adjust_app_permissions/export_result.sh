#!/system/bin/sh
# Export script for adjust_app_permissions task
# Captures final permission state and screenshot

echo "=== Exporting permission results ==="

PACKAGE="com.robert.fcView"
RESULT_FILE="/sdcard/task_result.json"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check Permission States via Dumpsys
# We check specific flags. Grep returns 0 if found, 1 if not.

# Check Background Location (Goal: Granted)
if dumpsys package $PACKAGE | grep "android.permission.ACCESS_BACKGROUND_LOCATION: granted=true"; then
    LOC_BG_GRANTED="true"
else
    LOC_BG_GRANTED="false"
fi

# Check Fine Location (Goal: Granted)
if dumpsys package $PACKAGE | grep "android.permission.ACCESS_FINE_LOCATION: granted=true"; then
    LOC_FG_GRANTED="true"
else
    LOC_FG_GRANTED="false"
fi

# Check Microphone (Goal: Not granted / Revoked)
# Note: "granted=true" should NOT be present for RECORD_AUDIO
if dumpsys package $PACKAGE | grep "android.permission.RECORD_AUDIO: granted=true"; then
    MIC_GRANTED="true"
else
    MIC_GRANTED="false"
fi

# Check Calendar (Goal: Granted)
if dumpsys package $PACKAGE | grep "android.permission.READ_CALENDAR: granted=true"; then
    CAL_GRANTED="true"
else
    CAL_GRANTED="false"
fi

# Check Contacts (Goal: Granted)
if dumpsys package $PACKAGE | grep "android.permission.READ_CONTACTS: granted=true"; then
    CONTACTS_GRANTED="true"
else
    CONTACTS_GRANTED="false"
fi

# 3. Check if App is in Foreground
# We dump window info and check if our package is focused
if dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' | grep "$PACKAGE"; then
    APP_IN_FOREGROUND="true"
else
    APP_IN_FOREGROUND="false"
fi

# 4. Create JSON Result
# Note: Android shell usually has limited JSON tools, constructing string manually
echo "{" > $RESULT_FILE
echo "  \"task_start\": $TASK_START," >> $RESULT_FILE
echo "  \"task_end\": $TASK_END," >> $RESULT_FILE
echo "  \"location_background_granted\": $LOC_BG_GRANTED," >> $RESULT_FILE
echo "  \"location_fine_granted\": $LOC_FG_GRANTED," >> $RESULT_FILE
echo "  \"microphone_granted\": $MIC_GRANTED," >> $RESULT_FILE
echo "  \"calendar_granted\": $CAL_GRANTED," >> $RESULT_FILE
echo "  \"contacts_granted\": $CONTACTS_GRANTED," >> $RESULT_FILE
echo "  \"app_in_foreground\": $APP_IN_FOREGROUND," >> $RESULT_FILE
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> $RESULT_FILE
echo "}" >> $RESULT_FILE

echo "Result JSON created at $RESULT_FILE"
cat $RESULT_FILE