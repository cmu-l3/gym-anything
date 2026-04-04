#!/bin/bash
# Export script for "create_asset_loan" task

echo "=== Exporting Asset Loan Result ==="
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export Database State to JSON
# We need to check:
# 1. Asset State (Should be 'On Loan' or equivalent)
# 2. Loan Record details (User, Dates, Comments)

# Helper to get JSON-safe string from DB
get_db_json() {
    local query="$1"
    # Use psql with json output if available, or manual csv-to-json construction
    # Since SDP postgres might be old, we'll fetch CSV and use python to format
    local res
    res=$(sdp_db_exec "$query")
    # Python one-liner to dump this string as JSON
    python3 -c "import json, sys; print(json.dumps(sys.argv[1]))" "$res"
}

echo "Querying Database..."

# 1. Get Asset State
# We assume state 'In Store' changed to 'On Loan'.
# We query the resource state name directly if possible, or the ID.
ASSET_STATE_RAW=$(sdp_db_exec "
SELECT rs.displaystate 
FROM resources r 
JOIN resourcestate rs ON r.resourcestateid = rs.resourcestateid 
WHERE r.assettag = 'AV-PROJ-005';
")

# 2. Get Loan Details
# We look for the most recent loan/resource owner change or specific loan table.
# Common tables: ResourceOwner history, AssetLoan, LoanDetails.
# We'll check 'ResourceOwner' as a proxy for assignment if Loan table is obscure,
# but SDP usually has 'assetloan' or 'loan' tables.
LOAN_DATA_RAW=$(sdp_db_exec "
SELECT 
    au.first_name, 
    al.loandate, 
    al.expectedreturndate, 
    al.comments 
FROM assetloan al
JOIN resources r ON al.resourceid = r.resourceid
JOIN aaauser au ON al.userid = au.user_id
WHERE r.assettag = 'AV-PROJ-005'
ORDER BY al.loandate DESC 
LIMIT 1;
")

# Construct JSON result
cat > /tmp/task_result.json << EOF
{
    "timestamp": $(date +%s),
    "asset_tag": "AV-PROJ-005",
    "asset_state": "$(echo $ASSET_STATE_RAW | tr -d '\n\r')",
    "loan_data_raw": "$(echo $LOAN_DATA_RAW | tr -d '\n\r')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Parse the pipe-delimited raw data in Python for better JSON structure if needed,
# but for now, raw string is sufficient for the verifier to parse.

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="