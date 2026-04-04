#!/bin/bash
# Export script for bulk_import_assets task

echo "=== Exporting Bulk Import Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Database for Results
# We need to verify:
# - Count of assets
# - Fields for a sample asset (DEV-SF-01)

# Helper to get JSON string from SQL query result
# We query 'resource' table (holds name, serial) and join 'component' (holds cost/warranty usually)
# Note: SDP schema varies. We'll query 'resource' which is standard.
# We'll fetch all columns for the sample asset to be safe.

# Query 1: Count of imported assets
ASSET_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM resource WHERE resourcename LIKE 'DEV-SF-%';")
log "Found $ASSET_COUNT assets matching 'DEV-SF-%'"

# Query 2: Get details of DEV-SF-01
# We try to get: resourcename, serialno, site (via siteid), cost (might be in assetdetails)
# We'll output a simple text format that python can parse
SAMPLE_DATA=$(sdp_db_exec "
SELECT 
    r.resourcename, 
    r.serialno, 
    s.sitename,
    r.addedtime 
FROM resource r 
LEFT JOIN sitedefinition s ON r.siteid = s.siteid 
WHERE r.resourcename = 'DEV-SF-01';
")

# Query 3: Check for Cost (often in component definition or assetdetails)
# We'll try to find cost in common tables.
COST_DATA=$(sdp_db_exec "
SELECT purchasecost FROM component 
WHERE componentid = (SELECT resourceid FROM resource WHERE resourcename = 'DEV-SF-01');
")
# Fallback if cost is in assetdetails
if [ -z "$COST_DATA" ]; then
    COST_DATA=$(sdp_db_exec "
    SELECT cost FROM assetdetails 
    WHERE assetid = (SELECT resourceid FROM resource WHERE resourcename = 'DEV-SF-01');
    ")
fi

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "asset_count": ${ASSET_COUNT:-0},
    "sample_asset": {
        "raw_data": "$SAMPLE_DATA",
        "cost_data": "$COST_DATA",
        "name_check": "$(echo "$SAMPLE_DATA" | grep -o 'DEV-SF-01' || echo '')",
        "serial_check": "$(echo "$SAMPLE_DATA" | grep -o 'C02XG1J2K3L4' || echo '')",
        "site_check": "$(echo "$SAMPLE_DATA" | grep -o 'San Francisco' || echo '')"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="