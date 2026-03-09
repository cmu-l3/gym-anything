#!/system/bin/sh
# Export script for check_running_memory
# Runs on Android environment

echo "=== Exporting Results ==="

# 1. Check Developer Options State
DEV_OPTIONS_ENABLED=$(settings get global development_settings_enabled)
# Clean up output (remove carriage returns etc)
DEV_OPTIONS_ENABLED=$(echo "$DEV_OPTIONS_ENABLED" | tr -d '\r\n')

# 2. Check Audit File
AUDIT_FILE="/sdcard/ram_audit.txt"
AUDIT_EXISTS="false"
AUDIT_CONTENT=""
if [ -f "$AUDIT_FILE" ]; then
    AUDIT_EXISTS="true"
    AUDIT_CONTENT=$(cat "$AUDIT_FILE")
fi

# 3. Check Evidence Screenshot
EVIDENCE_FILE="/sdcard/ram_evidence.png"
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_FILE" ]; then
    EVIDENCE_EXISTS="true"
fi

# 4. Create JSON payload
# Note: Android shell usually doesn't have jq, so we construct JSON manually
# We need to escape quotes in content if any
SAFE_CONTENT=$(echo "$AUDIT_CONTENT" | sed 's/"/\\"/g')

echo "{" > /sdcard/task_result.json
echo "  \"dev_options_enabled\": \"$DEV_OPTIONS_ENABLED\"," >> /sdcard/task_result.json
echo "  \"audit_file_exists\": $AUDIT_EXISTS," >> /sdcard/task_result.json
echo "  \"audit_content\": \"$SAFE_CONTENT\"," >> /sdcard/task_result.json
echo "  \"evidence_screenshot_exists\": $EVIDENCE_EXISTS" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json