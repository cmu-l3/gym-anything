#!/bin/bash
set -e
echo "=== Exporting Create BP Group and Customer Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Database for BP Group
# Returns JSON object or null
echo "Querying BP Group..."
GROUP_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT row_to_json(t) FROM (
    SELECT 
        c_bp_group_id, 
        value as search_key, 
        name, 
        extract(epoch from created) as created_ts 
    FROM c_bp_group 
    WHERE name='Botanical Gardens' AND ad_client_id=11
) t
" 2>/dev/null || echo "")

if [ -z "$GROUP_JSON" ]; then GROUP_JSON="null"; fi

# 4. Query Database for Business Partner
# Returns JSON object or null
echo "Querying Business Partner..."
BP_JSON=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "
SELECT row_to_json(t) FROM (
    SELECT 
        c_bpartner_id, 
        value as search_key, 
        name, 
        c_bp_group_id, 
        iscustomer, 
        extract(epoch from created) as created_ts 
    FROM c_bpartner 
    WHERE name='City Botanical Garden' AND ad_client_id=11
) t
" 2>/dev/null || echo "")

if [ -z "$BP_JSON" ]; then BP_JSON="null"; fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "group_data": $GROUP_JSON,
    "bp_data": $BP_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Data saved to /tmp/task_result.json"
cat /tmp/task_result.json