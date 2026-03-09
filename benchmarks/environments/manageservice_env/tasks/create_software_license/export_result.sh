#!/bin/bash
echo "=== Exporting create_software_license result ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_license_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# QUERY DATABASE FOR RESULT
# ==============================================================================
# We search for the record created by the agent based on key characteristics
# We try to be robust against slight schema variations across SDP versions

echo "Querying database for software license..."

# Strategy: Find record where name is like Adobe or Key is like ACCA...
# We select relevant columns

# 1. Search by Name
SQL_QUERY="SELECT software_name, no_of_licenses, license_key, TO_CHAR(purchased_date, 'YYYY-MM-DD'), TO_CHAR(expiry_date, 'YYYY-MM-DD'), manufacturer, purchase_cost, license_type FROM softwarelicense WHERE LOWER(software_name) LIKE '%adobe%creative%cloud%' OR LOWER(software_name) LIKE '%all apps%' ORDER BY license_id DESC LIMIT 1;"

RECORD_DATA=$(sdp_db_exec "$SQL_QUERY" 2>/dev/null)

# If empty, try searching by License Key
if [ -z "$RECORD_DATA" ]; then
    SQL_QUERY_ALT="SELECT software_name, no_of_licenses, license_key, TO_CHAR(purchased_date, 'YYYY-MM-DD'), TO_CHAR(expiry_date, 'YYYY-MM-DD'), manufacturer, purchase_cost, license_type FROM softwarelicense WHERE license_key LIKE '%ACCA-2024%' ORDER BY license_id DESC LIMIT 1;"
    RECORD_DATA=$(sdp_db_exec "$SQL_QUERY_ALT" 2>/dev/null)
fi

# Get current total count
CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM softwarelicense;" 2>/dev/null || echo "0")
if [ -z "$CURRENT_COUNT" ]; then
    CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM componentdefinition WHERE ci_type LIKE '%Software%' OR ci_type LIKE '%License%';" 2>/dev/null || echo "0")
fi

# Parse the pipe-delimited output from psql (assuming standard format)
# If psql returns "Name|25|Key|Date|Date|Mfr|Cost|Type"
FOUND="false"
REC_NAME=""
REC_COUNT=""
REC_KEY=""
REC_PURCHASE=""
REC_EXPIRY=""
REC_MFR=""
REC_COST=""
REC_TYPE=""

if [ -n "$RECORD_DATA" ]; then
    FOUND="true"
    # IFS='|' read -r REC_NAME REC_COUNT REC_KEY REC_PURCHASE REC_EXPIRY REC_MFR REC_COST REC_TYPE <<< "$RECORD_DATA"
    # Using awk to be safer with delimiter handling
    REC_NAME=$(echo "$RECORD_DATA" | cut -d'|' -f1)
    REC_COUNT=$(echo "$RECORD_DATA" | cut -d'|' -f2)
    REC_KEY=$(echo "$RECORD_DATA" | cut -d'|' -f3)
    REC_PURCHASE=$(echo "$RECORD_DATA" | cut -d'|' -f4)
    REC_EXPIRY=$(echo "$RECORD_DATA" | cut -d'|' -f5)
    REC_MFR=$(echo "$RECORD_DATA" | cut -d'|' -f6)
    REC_COST=$(echo "$RECORD_DATA" | cut -d'|' -f7)
    REC_TYPE=$(echo "$RECORD_DATA" | cut -d'|' -f8)
fi

# Sanitize strings for JSON (escape quotes)
REC_NAME="${REC_NAME//\"/\\\"}"
REC_KEY="${REC_KEY//\"/\\\"}"
REC_MFR="${REC_MFR//\"/\\\"}"
REC_TYPE="${REC_TYPE//\"/\\\"}"

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "record_found": $FOUND,
    "record": {
        "name": "$REC_NAME",
        "count": "$REC_COUNT",
        "key": "$REC_KEY",
        "purchase_date": "$REC_PURCHASE",
        "expiry_date": "$REC_EXPIRY",
        "manufacturer": "$REC_MFR",
        "cost": "$REC_COST",
        "type": "$REC_TYPE"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="