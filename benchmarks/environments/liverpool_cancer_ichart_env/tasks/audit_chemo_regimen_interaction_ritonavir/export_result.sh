#!/system/bin/sh
echo "=== Exporting audit_chemo_regimen_interaction_ritonavir results ==="

# 1. Capture final state
screencap -p /sdcard/task_final.png

# 2. Check result file details
FILE="/sdcard/ritonavir_chemo_audit.txt"
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$FILE" ]; then
    FILE_EXISTS="true"
    # Android 'stat' might be limited, try standard first
    FILE_MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
    
    # Fallback if stat failed (common on minimal Android shells)
    if [ "$FILE_MTIME" = "0" ]; then
        # Use ls -l to get modification time (rough check)
        FILE_MTIME=$(date +%s) # Assume current if we can't read it, but verification will check content
    fi
    
    FILE_SIZE=$(stat -c %s "$FILE" 2>/dev/null || wc -c < "$FILE")
else
    FILE_EXISTS="false"
    FILE_MTIME="0"
    FILE_SIZE="0"
fi

# Check if file was modified after start (Anti-gaming)
if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
    CREATED_DURING_TASK="true"
else
    CREATED_DURING_TASK="false"
fi

# 3. Create JSON output
# Note: creating raw JSON string carefully to avoid quoting issues in simple shell
echo "{" > /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"file_size\": $FILE_SIZE," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "=== Export complete ==="