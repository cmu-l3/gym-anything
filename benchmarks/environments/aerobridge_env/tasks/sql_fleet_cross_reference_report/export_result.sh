#!/bin/bash
# export_result.sh — post_task hook for sql_fleet_cross_reference_report

echo "=== Exporting SQL Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic File Checks
REPORT_PATH="/home/ga/Documents/fleet_sql_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING="false"
CONTENT_SNIPPET=""

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
    
    # Read content for analysis (escape for JSON)
    # We take the first 50 lines to keep JSON manageable, verifier can assume if header matches it's good
    CONTENT_SNIPPET=$(head -n 50 "$REPORT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    CONTENT_SNIPPET="\"\""
fi

# 3. Analyze Bash History for sqlite3 usage (Anti-gaming/Process verification)
# Look for 'sqlite3' command in history files
HISTORY_MATCH="false"
if grep -q "sqlite3" /home/ga/.bash_history 2>/dev/null; then
    HISTORY_MATCH="true"
fi
# Also check currently running or recent processes if possible, but history is best for past actions

# 4. Prepare Ground Truth for export
if [ -f /tmp/ground_truth.json ]; then
    GROUND_TRUTH=$(cat /tmp/ground_truth.json)
else
    GROUND_TRUTH="{}"
fi

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING,
    "bash_history_sqlite_match": $HISTORY_MATCH,
    "ground_truth": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png",
    "report_content_snippet": $CONTENT_SNIPPET,
    "report_path_internal": "$REPORT_PATH"
}
EOF

# 6. Read full file content safely into a Python script to do deep content analysis
#    (We do this analysis here to avoid passing huge strings in JSON if possible, 
#     or we can just let the verifier do it if we copy the text file out. 
#     Let's copy the text file out via the verifier's copy_from_env, 
#     so we just need to ensure permissions are good.)

chmod 644 "$REPORT_PATH" 2>/dev/null || true
chmod 644 /tmp/task_result.json

echo "Export complete. Result JSON:"
cat /tmp/task_result.json