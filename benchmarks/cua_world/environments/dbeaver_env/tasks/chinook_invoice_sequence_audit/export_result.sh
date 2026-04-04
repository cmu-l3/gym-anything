#!/bin/bash
# Export script for chinook_invoice_sequence_audit
# Collects evidence: CSV output, SQL script, connection state, screenshots

echo "=== Exporting Audit Results ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_CSV="/home/ga/Documents/exports/gap_analysis.csv"
OUTPUT_SQL="/home/ga/Documents/scripts/audit_query.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
GROUND_TRUTH_FILE="/tmp/audit_ground_truth.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if CSV exists and analyze it
CSV_EXISTS=false
CSV_CONTENT=""
CSV_HEADER=""
if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS=true
    # Read the content for the verifier (limit size)
    CSV_CONTENT=$(cat "$OUTPUT_CSV" | head -n 20)
    CSV_HEADER=$(head -n 1 "$OUTPUT_CSV")
fi

# 2. Check if SQL script exists
SQL_EXISTS=false
if [ -f "$OUTPUT_SQL" ]; then
    SQL_EXISTS=true
fi

# 3. Check for DBeaver Connection 'ChinookAudit'
CONNECTION_FOUND=false
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple grep check for the connection name in the config file
    if grep -q "ChinookAudit" "$DBEAVER_CONFIG"; then
        CONNECTION_FOUND=true
    fi
fi

# 4. Check timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_MODIFIED_TIME=0
if [ -f "$OUTPUT_CSV" ]; then
    CSV_MODIFIED_TIME=$(stat -c %Y "$OUTPUT_CSV")
fi

FILE_CREATED_DURING_TASK=false
if [ "$CSV_MODIFIED_TIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK=true
fi

# 5. Load Ground Truth
GT_CONTENT="{}"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH_FILE")
fi

# Create result JSON
# We embed the CSV content directly so the verifier can parse it easily
# without needing complex file transfer logic if copy_from_env is strict.
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_header": "$(echo "$CSV_HEADER" | sed 's/"/\\"/g')",
    "csv_content_sample": "$(echo "$CSV_CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')",
    "sql_exists": $SQL_EXISTS,
    "connection_found": $CONNECTION_FOUND,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ground_truth": $GT_CONTENT
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="