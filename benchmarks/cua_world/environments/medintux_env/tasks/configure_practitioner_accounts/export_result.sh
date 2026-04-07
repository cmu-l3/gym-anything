#!/bin/bash
set -e
echo "=== Exporting configure_practitioner_accounts result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Database State Export ---
# We need to find where the agent inserted the data.
# We'll search for the login 'mlefebvre' in all tables in DrTuxTest.

DB_USER="root"
DB_NAME="DrTuxTest"
FOUND_TABLE=""
USER_DATA_JSON="[]"

echo "Searching for inserted records..."

# Get list of all tables
TABLES=$(mysql -u $DB_USER $DB_NAME -N -e "SHOW TABLES")

for tbl in $TABLES; do
    # Check if this table contains the user 'mlefebvre'
    # We try generic queries because we don't know column names for sure,
    # but we can try to grep the raw output of a SELECT *
    
    # Efficient way: check if any column has the value 'mlefebvre'
    # constructing a query is hard without knowing schema.
    # Simpler: Select all rows where any likely column matches, or just dump the table if small.
    # Given typical user tables are small, we can check count.
    
    # Try to find column names first
    COLUMNS=$(mysql -u $DB_USER $DB_NAME -N -e "DESCRIBE $tbl" | awk '{print $1}')
    
    IS_TARGET_TABLE="false"
    for col in $COLUMNS; do
        COUNT=$(mysql -u $DB_USER $DB_NAME -N -e "SELECT COUNT(*) FROM $tbl WHERE $col='mlefebvre'" 2>/dev/null || echo "0")
        if [ "$COUNT" -gt 0 ]; then
            FOUND_TABLE="$tbl"
            LOGIN_COL="$col"
            IS_TARGET_TABLE="true"
            break
        fi
    done
    
    if [ "$IS_TARGET_TABLE" = "true" ]; then
        echo "Found user 'mlefebvre' in table: $FOUND_TABLE (column: $LOGIN_COL)"
        
        # Export the rows for both target users as JSON
        # We use a python one-liner to dump the query result to JSON
        QUERY="SELECT * FROM $FOUND_TABLE WHERE $LOGIN_COL IN ('mlefebvre', 'smartin')"
        
        USER_DATA_JSON=$(mysql -u $DB_USER $DB_NAME -e "$QUERY" | python3 -c '
import sys, json, csv
reader = csv.DictReader(sys.stdin, delimiter="\t")
print(json.dumps(list(reader)))
')
        break
    fi
done

# --- Report File Check ---
REPORT_PATH="/home/ga/practitioner_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH")
    # Read first 2KB of report for verification
    REPORT_CONTENT=$(head -c 2048 "$REPORT_PATH")
fi

# --- Create Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found_table": "$FOUND_TABLE",
    "user_data": $USER_DATA_JSON,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_content_preview": $(echo "$REPORT_CONTENT" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))'),
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
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