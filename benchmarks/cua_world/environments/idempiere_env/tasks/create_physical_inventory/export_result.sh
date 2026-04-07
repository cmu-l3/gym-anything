#!/bin/bash
echo "=== Exporting create_physical_inventory result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_inventory_count.txt 2>/dev/null || echo "0")

# 3. Query the database for the result
# We look for the MOST RECENT inventory record matching the description, 
# or simply the most recent one created after start time.

CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# Helper to run query and escape JSON output
query_json() {
    local sql="$1"
    # psql -t (tuples only) -A (no align) to get raw output
    docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "$sql" 2>/dev/null
}

echo "Querying database for Physical Inventory..."

# Find the Inventory ID (M_Inventory_ID)
# We prioritize exact description match created recently
INVENTORY_ID=$(query_json "
    SELECT m_inventory_id 
    FROM m_inventory 
    WHERE ad_client_id=$CLIENT_ID 
    AND description='Year-End Count Q4 2024' 
    AND isactive='Y'
    ORDER BY created DESC LIMIT 1
")

# If not found by description, check if ANY new inventory was created (fallback for partial credit)
if [ -z "$INVENTORY_ID" ]; then
    CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inventory WHERE ad_client_id=$CLIENT_ID")
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
         INVENTORY_ID=$(query_json "
            SELECT m_inventory_id 
            FROM m_inventory 
            WHERE ad_client_id=$CLIENT_ID 
            ORDER BY created DESC LIMIT 1
        ")
    fi
fi

# Prepare result JSON
JSON_CONTENT="{
    \"task_start\": $TASK_START,
    \"task_end\": $TASK_END,
    \"initial_count\": $INITIAL_COUNT,
    \"record_found\": false
}"

if [ -n "$INVENTORY_ID" ]; then
    # Fetch Header Details
    HEADER_JSON=$(query_json "
        SELECT row_to_json(t) FROM (
            SELECT 
                i.description,
                i.movementdate as movement_date,
                i.docstatus,
                w.value as warehouse_value,
                w.name as warehouse_name,
                EXTRACT(EPOCH FROM i.created) as created_ts
            FROM m_inventory i
            JOIN m_warehouse w ON i.m_warehouse_id = w.m_warehouse_id
            WHERE i.m_inventory_id = $INVENTORY_ID
        ) t
    ")

    # Fetch Line Details
    LINES_JSON=$(query_json "
        SELECT json_agg(t) FROM (
            SELECT 
                p.name as product_name,
                p.value as product_key,
                il.qtycount,
                il.qtybook
            FROM m_inventoryline il
            JOIN m_product p ON il.m_product_id = p.m_product_id
            WHERE il.m_inventory_id = $INVENTORY_ID
            ORDER BY il.line
        ) t
    ")
    
    # Default empty array if null
    if [ -z "$LINES_JSON" ]; then LINES_JSON="[]"; fi

    # Combine into final JSON
    JSON_CONTENT="{
        \"task_start\": $TASK_START,
        \"task_end\": $TASK_END,
        \"initial_count\": $INITIAL_COUNT,
        \"record_found\": true,
        \"inventory_id\": $INVENTORY_ID,
        \"header\": $HEADER_JSON,
        \"lines\": $LINES_JSON
    }"
fi

# Save to temp file with safe permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$JSON_CONTENT" > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json
echo "=== Export finished ==="