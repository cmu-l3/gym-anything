#!/bin/bash
echo "=== Exporting Configure Secure Archiving results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query Database for Archive Configuration
# We query multiple potential tables/columns where ME stores these settings.
# We look for the retention value '365' and encryption flags.

echo "Querying database for archive configuration..."
DB_DUMP_FILE="/tmp/db_config_dump.txt"

# Query 1: GlobalConfig (Common for ME apps)
echo "--- GlobalConfig ---" > "$DB_DUMP_FILE"
ela-db-query "SELECT * FROM GlobalConfig ORDER BY paramname" >> "$DB_DUMP_FILE" 2>/dev/null

# Query 2: SystemSettings / SystemConfiguration
echo "--- SystemSettings ---" >> "$DB_DUMP_FILE"
ela-db-query "SELECT * FROM SystemSettings" >> "$DB_DUMP_FILE" 2>/dev/null
ela-db-query "SELECT * FROM SystemConfiguration" >> "$DB_DUMP_FILE" 2>/dev/null

# Query 3: Specific search for our target values (in case schema differs)
echo "--- Value Search ---" >> "$DB_DUMP_FILE"
# Check for 365 in any config-like tables
ela-db-query "SELECT * FROM GlobalConfig WHERE paramvalue LIKE '%365%'" >> "$DB_DUMP_FILE" 2>/dev/null

# Check specific parameters often used by EventLog Analyzer
# ARCHIVE_ENABLE, ARCHIVE_RETENTION_PERIOD, ENCRYPT_ARCHIVE, ZIP_PASSWORD
ela-db-query "SELECT * FROM GlobalConfig WHERE paramname IN ('ARCHIVE_RETENTION_PERIOD', 'ARCHIVE_ENCRYPTION', 'ENCRYPT_ARCHIVE', 'ARCHIVE_PASSWORD')" >> "$DB_DUMP_FILE" 2>/dev/null

# Check if file was created/modified during task
DB_MODIFIED="false"
if [ -f "$DB_DUMP_FILE" ]; then
    # Simple check: does the dump contain the target value '365'?
    if grep -q "365" "$DB_DUMP_FILE"; then
        DB_MODIFIED="true"
    fi
fi

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Read specific values into variables for JSON
# Extract retention period (looking for numeric 365 in value column)
RETENTION_FOUND=$(grep -i "365" "$DB_DUMP_FILE" | head -1 || echo "")

# Extract encryption status (looking for 'true' or '1' associated with encryption keys)
ENCRYPTION_FOUND=$(grep -iE "encrypt.*(true|1|yes)" "$DB_DUMP_FILE" | head -1 || echo "")
if [ -z "$ENCRYPTION_FOUND" ]; then
    # Check if a password entry exists (implies encryption enabled)
    ENCRYPTION_FOUND=$(grep -iE "(password|pwd).*(Secure|Log|Pass)" "$DB_DUMP_FILE" | head -1 || echo "")
fi

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_dump_path": "$DB_DUMP_FILE",
    "retention_value_found": "$RETENTION_FOUND",
    "encryption_config_found": "$ENCRYPTION_FOUND",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="