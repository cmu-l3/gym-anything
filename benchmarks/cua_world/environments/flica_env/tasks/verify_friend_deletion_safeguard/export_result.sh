#!/system/bin/sh
echo "=== Exporting verify_friend_deletion_safeguard results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
screencap -p /sdcard/task_final.png

# Dump UI hierarchy to check for text persistence programmatically
uiautomator dump /sdcard/final_ui.xml 2>/dev/null

# Check if "Safeguard Pilot" is present in the final UI
FRIEND_FOUND="false"
if [ -f /sdcard/final_ui.xml ]; then
    if grep -q "Safeguard Pilot" /sdcard/final_ui.xml; then
        FRIEND_FOUND="true"
    fi
fi

# Create JSON result
# Note: writing to sdcard ensures we can copy it out later
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"friend_found\": $FRIEND_FOUND" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="