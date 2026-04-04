#!/system/bin/sh
# Export script for evaluate_malaria_prophylaxis_nilotinib task

echo "=== Exporting Task Results ==="

REPORT_PATH="/sdcard/nilotinib_malaria_report.txt"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. check if report file exists and get stats
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(ls -l "$REPORT_PATH" | awk '{print $4}')
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_PATH")
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    REPORT_CONTENT=""
fi

# 3. Check if file was modified after start (anti-gaming)
# Note: Android shell might not have stat -c %Y easily, so we rely on existence for now
# or compare against start time if we could get mtimes. 
# We'll rely on python verifier to check creation time relative to task start if needed,
# but file content verification is the primary signal here.

# 4. Create a simple JSON result file (manual construction for sh compatibility)
# We avoid complex JSON escaping in shell and verify the text file content directly in Python.
# This JSON serves as a quick status check.
echo "{" > "$RESULT_JSON"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$RESULT_JSON"
echo "  \"report_size\": $REPORT_SIZE," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"