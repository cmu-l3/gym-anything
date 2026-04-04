#!/system/bin/sh
# export_result.sh for track_flight_alert@1
# Captures final state, checks app status, and exports evidence

echo "=== Exporting track_flight_alert results ==="

PACKAGE="com.robert.fcView"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check if App is Running
APP_RUNNING="false"
if pidof "$PACKAGE" > /dev/null 2>&1 || pm list packages | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# 2. Capture Final Screenshot
screencap -p /sdcard/task_final_screenshot.png 2>/dev/null
SCREENSHOT_EXISTS="false"
if [ -f /sdcard/task_final_screenshot.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 3. Dump Final UI State
uiautomator dump /sdcard/final_ui_state.xml 2>/dev/null

# 4. programmatic Checks on UI Content
FLIGHT_TEXT_FOUND="false"
DL400_FOUND="false"
TRACK_KEYWORD_FOUND="false"
UI_CHANGED="false"

if [ -f /sdcard/final_ui_state.xml ]; then
    UI_CONTENT=$(cat /sdcard/final_ui_state.xml)
    
    # Check for flight-related generic terms
    if echo "$UI_CONTENT" | grep -iq "flight\|track\|search\|depart\|arriv\|status\|schedule"; then
        FLIGHT_TEXT_FOUND="true"
    fi
    
    # Check for specific flight number "DL400" (case insensitive)
    if echo "$UI_CONTENT" | grep -iq "DL400\|DL 400\|Delta 400\|DAL400"; then
        DL400_FOUND="true"
    fi
    
    # Check for tracking/alert specific keywords
    if echo "$UI_CONTENT" | grep -iq "track\|follow\|alert\|notify\|watching\|monitor\|added"; then
        TRACK_KEYWORD_FOUND="true"
    fi
    
    # Check against initial hash
    if [ -f /sdcard/initial_ui_hash.txt ]; then
        INITIAL_HASH=$(cat /sdcard/initial_ui_hash.txt)
        FINAL_HASH=$(md5sum /sdcard/final_ui_state.xml | cut -d' ' -f1)
        if [ "$INITIAL_HASH" != "$FINAL_HASH" ]; then
            UI_CHANGED="true"
        fi
    else
        # If initial hash missing, assume changed if content is different from generic empty
        UI_CHANGED="true"
    fi
fi

# 5. Create JSON Result
# Using a temporary file pattern to ensure atomic write/permissions
TEMP_JSON="/sdcard/temp_result.json"
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$TEMP_JSON"
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> "$TEMP_JSON"
echo "  \"ui_changed\": $UI_CHANGED," >> "$TEMP_JSON"
echo "  \"flight_text_found\": $FLIGHT_TEXT_FOUND," >> "$TEMP_JSON"
echo "  \"dl400_found\": $DL400_FOUND," >> "$TEMP_JSON"
echo "  \"track_keyword_found\": $TRACK_KEYWORD_FOUND," >> "$TEMP_JSON"
echo "  \"final_xml_path\": \"/sdcard/final_ui_state.xml\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Move to final location
mv "$TEMP_JSON" /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="