#!/bin/bash
# Export results for "import_csv_app_logs" task

echo "=== Exporting Import CSV Results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query Database for Imported Events
# We look for the specific error message generated in setup
TARGET_MSG="Database connection lost during batch processing"
TARGET_HOST="PAYROLL-DB"

# Query to get details of the specific event
# Note: ELA tables differ by version, but SystemLog or similar usually holds generic logs.
# We try a broad query. Columns often include: 
#   TIMERECEIVED (bigint), SEVERITY (int), SOURCE (varchar), MESSAGE (varchar)
# We select fields separated by '|'
echo "Querying database for imported events..."

# We try to get the record corresponding to the Error event
DB_RECORD=$(ela_db_query "SELECT SEVERITY, SOURCE, MESSAGE FROM SystemLog WHERE MESSAGE LIKE '%$TARGET_MSG%' LIMIT 1" 2>/dev/null)

if [ -z "$DB_RECORD" ]; then
    # Fallback: Try 'LogData' or 'EventLog' table if SystemLog is empty
    DB_RECORD=$(ela_db_query "SELECT SEVERITY, SOURCE, MESSAGE FROM EventLog WHERE MESSAGE LIKE '%$TARGET_MSG%' LIMIT 1" 2>/dev/null)
fi

# Count total imported rows from our CSV
TOTAL_IMPORTED=$(ela_db_query "SELECT COUNT(*) FROM SystemLog WHERE MESSAGE LIKE '%PAYROLL-DB%'" 2>/dev/null)
if [ -z "$TOTAL_IMPORTED" ] || [ "$TOTAL_IMPORTED" -eq 0 ]; then
     TOTAL_IMPORTED=$(ela_db_query "SELECT COUNT(*) FROM EventLog WHERE MESSAGE LIKE '%PAYROLL-DB%'" 2>/dev/null)
fi
if [ -z "$TOTAL_IMPORTED" ]; then TOTAL_IMPORTED="0"; fi

# Get Initial Count
INITIAL_COUNT=$(cat /tmp/initial_payroll_count.txt 2>/dev/null || echo "0")

# 2. Check File Access (Anti-gaming)
CSV_FILE="/home/ga/Documents/payroll_logs.csv"
FILE_ACCESSED="false"
if [ -f "$CSV_FILE" ]; then
    # check access time
    ATIME=$(stat -c %X "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$ATIME" -gt "$TASK_START" ]; then
        FILE_ACCESSED="true"
    fi
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct JSON Result
# DB_RECORD format expected: "SEVERITY_VAL|SOURCE_VAL|MESSAGE_VAL"
# We need to map severity number to name if it's an int. 
# Usually in ELA/Syslog: 1=Debug... 3=Error, etc. Or it might be stored as string.
# We pass the raw string to python verifier to parse.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "total_imported": $TOTAL_IMPORTED,
    "db_record_raw": "$DB_RECORD",
    "file_accessed": $FILE_ACCESSED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json