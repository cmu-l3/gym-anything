#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_contract result ==="

# 1. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Timing Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_contract_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Contract Details
# We look for the specific contract created by the agent
echo "Querying database for contract details..."

# Helper to escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n'
}

# Find the contract ID (max ID matching name)
CONTRACT_ID=$(sdp_db_exec "SELECT contractid FROM contractinfo WHERE LOWER(contractname) LIKE '%cisco%smartnet%' ORDER BY contractid DESC LIMIT 1;" 2>/dev/null || echo "")

CONTRACT_FOUND="false"
CONTRACT_DATA="{}"

if [ -n "$CONTRACT_ID" ]; then
    CONTRACT_FOUND="true"
    
    # Extract fields individually to build safe JSON
    NAME=$(sdp_db_exec "SELECT contractname FROM contractinfo WHERE contractid=$CONTRACT_ID;" 2>/dev/null)
    NUMBER=$(sdp_db_exec "SELECT contractnumber FROM contractinfo WHERE contractid=$CONTRACT_ID;" 2>/dev/null)
    # Check both 'cost' and 'totalcost' columns as schema varies by version
    COST=$(sdp_db_exec "SELECT COALESCE(totalcost, cost, 0) FROM contractinfo WHERE contractid=$CONTRACT_ID;" 2>/dev/null)
    DESC=$(sdp_db_exec "SELECT description FROM contractinfo WHERE contractid=$CONTRACT_ID;" 2>/dev/null)
    
    # Dates are often stored as BigInt (ms) or Timestamps. retrieve as string if possible.
    # We grab raw value first
    START_DATE=$(sdp_db_exec "SELECT from_date FROM contractinfo WHERE contractid=$CONTRACT_ID;" 2>/dev/null)
    END_DATE=$(sdp_db_exec "SELECT expiry_date FROM contractinfo WHERE contractid=$CONTRACT_ID;" 2>/dev/null)
    
    # Get Vendor Name via join
    VENDOR_NAME=$(sdp_db_exec "SELECT v.vendorname FROM vendordetails v JOIN contractinfo c ON c.vendorid = v.vendorid WHERE c.contractid=$CONTRACT_ID;" 2>/dev/null)

    # Build the JSON object for the contract
    CONTRACT_DATA=$(cat <<EOF
    {
        "id": "$CONTRACT_ID",
        "name": "$(escape_json "$NAME")",
        "number": "$(escape_json "$NUMBER")",
        "cost": "${COST:-0}",
        "description": "$(escape_json "$DESC")",
        "start_date_raw": "${START_DATE:-0}",
        "end_date_raw": "${END_DATE:-0}",
        "vendor_name": "$(escape_json "$VENDOR_NAME")"
    }
EOF
)
fi

# 4. Get Current Count
CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM contractinfo;" 2>/dev/null || echo "0")

# 5. Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "contract_found": $CONTRACT_FOUND,
    "contract_details": $CONTRACT_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="