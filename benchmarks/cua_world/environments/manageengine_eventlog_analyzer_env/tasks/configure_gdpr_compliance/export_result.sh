#!/bin/bash
echo "=== Exporting GDPR Compliance Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Capture Final State Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check for Output File (PDF or CSV)
OUTPUT_DIR="/home/ga/Documents"
PDF_PATH="$OUTPUT_DIR/gdpr_compliance_report.pdf"
CSV_PATH="$OUTPUT_DIR/gdpr_compliance_report.csv"

FILE_FOUND="none"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$PDF_PATH" ]; then
    FILE_FOUND="pdf"
    FILE_SIZE=$(stat -c %s "$PDF_PATH")
    FILE_MTIME=$(stat -c %Y "$PDF_PATH")
elif [ -f "$CSV_PATH" ]; then
    FILE_FOUND="csv"
    FILE_SIZE=$(stat -c %s "$CSV_PATH")
    FILE_MTIME=$(stat -c %Y "$CSV_PATH")
fi

# 4. Verify Timestamp (Anti-Gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$FILE_FOUND" != "none" ]; then
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 5. Check Database for GDPR Configuration (Secondary Signal)
# Query table AaaUserStatus or similar to see if user accessed compliance
# Since schema is complex, we'll check if any recent reports were generated in the DB
# (Using a generic query for recent activities if possible, or relying on file + VLM)
DB_ACTIVITY_DETECTED="false"
# Simple check: count rows in standard log tables increased? (Proxy for system activity)
# A more specific query would require exact ELA schema knowledge which varies by version.
# We will rely on file creation + VLM, but check if DB is responsive.
if ela_db_query "SELECT 1" | grep -q "1"; then
    DB_ACCESSIBLE="true"
else
    DB_ACCESSIBLE="false"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_found": "$FILE_FOUND",
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "db_accessible": $DB_ACCESSIBLE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json