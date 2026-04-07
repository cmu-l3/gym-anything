#!/bin/bash
set -e
echo "=== Exporting configure_import_format results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# Query the Database for the Result
# ------------------------------------------------------------------
# We need to fetch:
# 1. The Import Format header (Name, Table, FormatType)
# 2. The Import Format Lines (Seq, Column, DataType)

# Define the expected name
TARGET_NAME="Legacy Customer Import"
CLIENT_ID=11 # GardenWorld

echo "Querying database for Import Format: '$TARGET_NAME'..."

# Fetch Header Info
# Note: FormatType 'C' = Comma Separated
# We join with AD_Table to get the readable table name
HEADER_QUERY="
SELECT 
    f.ad_impformat_id,
    f.name,
    t.tablename,
    f.formattype,
    f.created
FROM ad_impformat f
JOIN ad_table t ON f.ad_table_id = t.ad_table_id
WHERE f.name = '$TARGET_NAME' 
  AND f.ad_client_id = $CLIENT_ID
ORDER BY f.created DESC
LIMIT 1;
"

# Execute Query using the helper function (returns pipe-separated values by default from psql -A -t)
HEADER_RESULT=$(idempiere_query "$HEADER_QUERY")

FORMAT_FOUND="false"
FORMAT_ID=""
FORMAT_NAME=""
TABLE_NAME=""
FORMAT_TYPE=""
CREATED_DATE=""
ROWS_JSON="[]"

if [ -n "$HEADER_RESULT" ]; then
    FORMAT_FOUND="true"
    # Parse the pipe-separated result
    FORMAT_ID=$(echo "$HEADER_RESULT" | cut -d'|' -f1)
    FORMAT_NAME=$(echo "$HEADER_RESULT" | cut -d'|' -f2)
    TABLE_NAME=$(echo "$HEADER_RESULT" | cut -d'|' -f3)
    FORMAT_TYPE=$(echo "$HEADER_RESULT" | cut -d'|' -f4)
    CREATED_DATE=$(echo "$HEADER_RESULT" | cut -d'|' -f5)

    echo "Found Format ID: $FORMAT_ID"
    
    # Fetch Rows (Format Fields)
    # Join with AD_Column to get the column name
    # We construct a JSON array directly via SQL for easier parsing in Python, 
    # or just fetch raw lines and process here. Let's fetch raw lines.
    ROWS_QUERY="
    SELECT 
        r.seqno,
        c.columnname,
        r.datatype
    FROM ad_impformat_row r
    JOIN ad_column c ON r.ad_column_id = c.ad_column_id
    WHERE r.ad_impformat_id = $FORMAT_ID
    ORDER BY r.seqno;
    "
    
    ROWS_RESULT=$(idempiere_query "$ROWS_QUERY")
    
    # Convert raw rows to JSON array
    # Example raw: 
    # 10|Value|S
    # 20|Name|S
    if [ -n "$ROWS_RESULT" ]; then
        # Use jq to build the array if available, or simple python script
        # Let's use a small python snippet to safely format the list
        ROWS_JSON=$(python3 -c "
import sys, json
lines = sys.argv[1].strip().split('\n')
rows = []
for line in lines:
    if not line: continue
    parts = line.split('|')
    if len(parts) >= 3:
        rows.append({
            'seq': int(parts[0]),
            'column': parts[1],
            'datatype': parts[2]
        })
print(json.dumps(rows))
" "$ROWS_RESULT")
    fi
fi

# ------------------------------------------------------------------
# Create Result JSON
# ------------------------------------------------------------------

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "format_found": $FORMAT_FOUND,
    "format_details": {
        "name": "$FORMAT_NAME",
        "table_name": "$TABLE_NAME",
        "format_type": "$FORMAT_TYPE",
        "created_timestamp": "$CREATED_DATE"
    },
    "format_rows": $ROWS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="