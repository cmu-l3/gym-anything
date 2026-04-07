#!/bin/bash
echo "=== Exporting save_emails_as_eml result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Check if Thunderbird is running
TB_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Archive the CaseFiles directory to safely bypass file-copy framework limitations
if [ -d "/home/ga/Documents/CaseFiles" ]; then
    cd /home/ga/Documents
    tar -czf /tmp/casefiles.tar.gz CaseFiles/ 2>/dev/null || true
else
    # Create an empty tarball to prevent verifier crashes
    tar -czf /tmp/casefiles.tar.gz -T /dev/null 2>/dev/null || true
fi

# Count files locally for logging
FILE_COUNT=$(find /home/ga/Documents/CaseFiles -type f 2>/dev/null | wc -l || echo "0")

# Write out the standardized task metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tb_running": $TB_RUNNING,
    "file_count": $FILE_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Migrate standard metadata to correct location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/casefiles.tar.gz 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="