#!/bin/bash
echo "=== Exporting task results ==="

REPORT_FILE="/home/ga/consistency_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Load Ground Truths securely created during setup
TRUTH_MISSING=$(grep "Missing:" /tmp/.task_truth | cut -d' ' -f2 2>/dev/null)
TRUTH_ORPHAN=$(grep "Orphan:" /tmp/.task_truth | cut -d' ' -f2 2>/dev/null)

EXISTS="false"
CREATED_DURING="false"
CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    EXISTS="true"
    # Check if the file was created/modified during the task to prevent anti-gaming
    MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$START_TIME" ]; then
        CREATED_DURING="true"
    fi
    # Use base64 to safely embed multiline user text into JSON
    CONTENT=$(cat "$REPORT_FILE" | base64 -w 0)
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $EXISTS,
    "created_during_task": $CREATED_DURING,
    "report_content_b64": "$CONTENT",
    "truth_missing": "$TRUTH_MISSING",
    "truth_orphan": "$TRUTH_ORPHAN"
}
EOF

# Safely copy to /tmp for verifier collection
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="