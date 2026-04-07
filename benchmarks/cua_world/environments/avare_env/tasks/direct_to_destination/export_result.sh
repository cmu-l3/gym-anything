#!/system/bin/sh
echo "=== Exporting Direct-To Destination task results ==="

PACKAGE="com.ds.avare"
TASK_START=$(cat /data/local/tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
screencap -p /data/local/tmp/task_final_state.png 2>/dev/null || true

# Initialize result variables
DESTINATION_FOUND="false"
WRONG_AIRPORT_FOUND="false"
FILES_MODIFIED="false"
MATCH_SOURCE=""

# Check internal app files for destination state
# We need to look into the app's private data directory
# Using run-as to access private app data

echo "Checking internal state files..."

# Method 1: Check shared preferences
PREFS_CONTENT=$(run-as $PACKAGE cat /data/data/$PACKAGE/shared_prefs/com.ds.avare_preferences.xml 2>/dev/null || echo "")

if echo "$PREFS_CONTENT" | grep -qi "KSAC\|Sacramento.*Executive\|>SAC<"; then
    echo "Found destination in Preferences"
    DESTINATION_FOUND="true"
    MATCH_SOURCE="preferences"
fi

if echo "$PREFS_CONTENT" | grep -qi "KSMF\|Sacramento.*International\|>SMF<"; then
    echo "Found WRONG destination (KSMF) in Preferences"
    WRONG_AIRPORT_FOUND="true"
fi

# Method 2: Check files directory (plan.txt, destination.txt, save.xml, or similar)
# We list files and check modification times if possible, then cat content
FILE_LIST=$(run-as $PACKAGE ls /data/data/$PACKAGE/files/ 2>/dev/null || echo "")

for file in $FILE_LIST; do
    # Check if file name looks relevant
    if echo "$file" | grep -qE "plan|dest|save|state|recent"; then
        CONTENT=$(run-as $PACKAGE cat "/data/data/$PACKAGE/files/$file" 2>/dev/null || echo "")
        
        # Check for target airport
        if echo "$CONTENT" | grep -qi "KSAC\|Sacramento.*Executive\|>SAC<"; then
             echo "Found destination in file: $file"
             DESTINATION_FOUND="true"
             MATCH_SOURCE="$file"
             
             # Check timestamp (rough check via stat if available, otherwise assume modified if content matches)
             FILE_TS=$(run-as $PACKAGE stat -c %Y "/data/data/$PACKAGE/files/$file" 2>/dev/null || echo "0")
             if [ "$FILE_TS" -gt "$TASK_START" ]; then
                 FILES_MODIFIED="true"
             fi
        fi
        
        # Check for wrong airport
        if echo "$CONTENT" | grep -qi "KSMF\|Sacramento.*International\|>SMF<"; then
             WRONG_AIRPORT_FOUND="true"
        fi
    fi
done

# If we found the destination but couldn't verify timestamp precisely, 
# we rely on the fact that we cleared files in setup.
if [ "$DESTINATION_FOUND" = "true" ] && [ "$FILES_MODIFIED" = "false" ]; then
    # Since we cleared specific files in setup, existence implies creation/modification
    FILES_MODIFIED="true"
fi

# Create JSON result
# Using a temp file in /data/local/tmp which is generally writable
TEMP_JSON="/data/local/tmp/task_result.json"

echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"destination_found\": $DESTINATION_FOUND," >> "$TEMP_JSON"
echo "  \"wrong_airport_found\": $WRONG_AIRPORT_FOUND," >> "$TEMP_JSON"
echo "  \"files_modified_during_task\": $FILES_MODIFIED," >> "$TEMP_JSON"
echo "  \"match_source\": \"$MATCH_SOURCE\"," >> "$TEMP_JSON"
echo "  \"screenshot_path\": \"/data/local/tmp/task_final_state.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

echo "Result JSON created at $TEMP_JSON"
cat "$TEMP_JSON"
echo "=== Export complete ==="