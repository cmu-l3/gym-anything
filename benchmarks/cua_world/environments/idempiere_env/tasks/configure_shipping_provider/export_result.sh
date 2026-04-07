#!/bin/bash
set -e
echo "=== Exporting Configure Shipping Provider Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 3. Query Database for Results
# We retrieve the Shipper details, linked BP name, and Freight details in one JSON structure.

# Helper function to escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n'
}

echo "Querying database for 'Speedy Delivery'..."

# Fetch Shipper ID and basic details
SHIPPER_DATA=$(idempiere_query "
    SELECT s.M_Shipper_ID, s.Name, s.Description, bp.Name, s.Created 
    FROM M_Shipper s
    LEFT JOIN C_BPartner bp ON s.C_BPartner_ID = bp.C_BPartner_ID
    WHERE s.Name='Speedy Delivery' AND s.AD_Client_ID=$CLIENT_ID
    ORDER BY s.Created DESC LIMIT 1
" 2>/dev/null)

SHIPPER_FOUND="false"
SHIPPER_ID=""
SHIPPER_NAME=""
SHIPPER_DESC=""
BP_NAME=""
CREATED_TS=""

if [ -n "$SHIPPER_DATA" ]; then
    SHIPPER_FOUND="true"
    # Parse pipe-separated values (psql default) - specific format depends on helper but usually simple
    # The helper `idempiere_query` uses -A -t (unaligned, tuples only), separator is usually pipe
    SHIPPER_ID=$(echo "$SHIPPER_DATA" | cut -d'|' -f1)
    SHIPPER_NAME=$(echo "$SHIPPER_DATA" | cut -d'|' -f2)
    SHIPPER_DESC=$(echo "$SHIPPER_DATA" | cut -d'|' -f3)
    BP_NAME=$(echo "$SHIPPER_DATA" | cut -d'|' -f4)
    CREATED_TS=$(echo "$SHIPPER_DATA" | cut -d'|' -f5)
fi

# Fetch Freight details if Shipper found
FREIGHT_FOUND="false"
FREIGHT_AMT="0"
FREIGHT_CURRENCY=""

if [ "$SHIPPER_FOUND" == "true" ] && [ -n "$SHIPPER_ID" ]; then
    FREIGHT_DATA=$(idempiere_query "
        SELECT f.FreightAmt, c.ISO_Code
        FROM M_Freight f
        LEFT JOIN C_Currency c ON f.C_Currency_ID = c.C_Currency_ID
        WHERE f.M_Shipper_ID=$SHIPPER_ID AND f.IsActive='Y'
        ORDER BY f.Created DESC LIMIT 1
    " 2>/dev/null)

    if [ -n "$FREIGHT_DATA" ]; then
        FREIGHT_FOUND="true"
        FREIGHT_AMT=$(echo "$FREIGHT_DATA" | cut -d'|' -f1)
        FREIGHT_CURRENCY=$(echo "$FREIGHT_DATA" | cut -d'|' -f2)
    fi
fi

# 4. Construct JSON Output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "shipper_found": $SHIPPER_FOUND,
    "shipper_details": {
        "name": "$(escape_json "$SHIPPER_NAME")",
        "description": "$(escape_json "$SHIPPER_DESC")",
        "linked_bp_name": "$(escape_json "$BP_NAME")",
        "created_timestamp": "$(escape_json "$CREATED_TS")"
    },
    "freight_found": $FREIGHT_FOUND,
    "freight_details": {
        "amount": "$FREIGHT_AMT",
        "currency": "$(escape_json "$FREIGHT_CURRENCY")"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save Result
# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="