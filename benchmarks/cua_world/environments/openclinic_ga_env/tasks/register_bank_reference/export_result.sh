#!/bin/bash
echo "=== Exporting Register Bank Reference Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Evidence
take_screenshot /tmp/task_final_screenshot.png

# 2. Query Database for Result
# We need to find if 'Equity Bank' exists now.
# We'll check OC_BANKS (most likely) and fallback to generic table search if needed.

echo "Searching for 'Equity Bank' in database..."

# Check OC_BANKS in ocadmin_dbo
BANK_RECORD=$(admin_query "SELECT OC_BANK_OBJECTID, OC_BANK_NAME, OC_BANK_XML FROM OC_BANKS WHERE OC_BANK_NAME LIKE '%Equity Bank%'" 2>/dev/null)

FOUND="false"
BANK_ID=""
BANK_NAME=""
RAW_DATA=""

if [ -n "$BANK_RECORD" ]; then
    FOUND="true"
    BANK_ID=$(echo "$BANK_RECORD" | awk '{print $1}')
    # Extract name (handling potential spaces)
    BANK_NAME=$(echo "$BANK_RECORD" | cut -f2)
    RAW_DATA="$BANK_RECORD"
    echo "Found in OC_BANKS: ID=$BANK_ID, Name=$BANK_NAME"
else
    # Fallback: Check if it's in a 'Banks' table (some versions vary)
    BANK_RECORD_ALT=$(admin_query "SELECT id, name FROM Banks WHERE name LIKE '%Equity Bank%'" 2>/dev/null)
    if [ -n "$BANK_RECORD_ALT" ]; then
        FOUND="true"
        BANK_ID=$(echo "$BANK_RECORD_ALT" | awk '{print $1}')
        BANK_NAME=$(echo "$BANK_RECORD_ALT" | cut -f2)
        RAW_DATA="$BANK_RECORD_ALT"
        echo "Found in Banks table: ID=$BANK_ID"
    fi
fi

# 3. Get Counts for Anti-Gaming
INITIAL_COUNT=$(cat /tmp/initial_bank_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(admin_query "SELECT COUNT(*) FROM OC_BANKS" 2>/dev/null || echo "0")

# 4. Check if App was used (Firefox running)
APP_RUNNING="false"
if pgrep -f firefox >/dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/bank_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo 0),
    "export_timestamp": $(date +%s),
    "bank_found": $FOUND,
    "bank_data": {
        "id": "$BANK_ID",
        "name": "$BANK_NAME",
        "raw": "$RAW_DATA"
    },
    "counts": {
        "initial": $INITIAL_COUNT,
        "current": $CURRENT_COUNT
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to standard location with broad permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="