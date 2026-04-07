#!/bin/bash
echo "=== Exporting record_production_run results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_production_count.txt 2>/dev/null || echo "0")

# 3. Query for the specific production record created during the task
# We look for a record for 'Patio Set' created after task start
CLIENT_ID=$(get_gardenworld_client_id)

echo "Searching for production record..."
# Note: created timestamp in database is usually UTC or server time. 
# We look for records with ID greater than what likely existed, or just filter by properties and recent creation.
# Postgres `now()` comparison is safer if timezones match, but checking raw data is more robust.

# Fetch the most recent production record for 'Patio Set'
# We join with M_Product to filter by name
RECORD_DATA=$(idempiere_query "
SELECT p.m_production_id, p.name, p.productionqty, p.created, pr.name
FROM m_production p
JOIN m_product pr ON p.m_product_id = pr.m_product_id
WHERE pr.name = 'Patio Set'
  AND p.ad_client_id = ${CLIENT_ID:-11}
ORDER BY p.created DESC, p.m_production_id DESC
LIMIT 1
" 2>/dev/null)

# Check if a record was found
FOUND="false"
PROD_ID=""
PROD_NAME=""
PROD_QTY=""
CREATED=""
PRODUCT_NAME=""

if [ -n "$RECORD_DATA" ]; then
    # Parse the pipe-delimited output (psql -A -t uses | by default)
    PROD_ID=$(echo "$RECORD_DATA" | cut -d'|' -f1)
    PROD_NAME=$(echo "$RECORD_DATA" | cut -d'|' -f2)
    PROD_QTY=$(echo "$RECORD_DATA" | cut -d'|' -f3)
    CREATED=$(echo "$RECORD_DATA" | cut -d'|' -f4)
    PRODUCT_NAME=$(echo "$RECORD_DATA" | cut -d'|' -f5)
    
    # Simple check if it's a new record (created timestamp check is complex in bash, 
    # relying on Verifier logic or if we see count increased)
    CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_production WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        FOUND="true"
    else
        # Fallback: if count didn't increase, maybe they updated an old one? 
        # But task says 'Create'. We'll pass the data to verifier to decide based on logic.
        # Ideally, we want a new record.
        FOUND="true" # Found *a* record, verifier checks if it's the right one
    fi
fi

# 4. If record found, fetch its lines (components)
LINES_JSON="[]"
if [ "$FOUND" = "true" ] && [ -n "$PROD_ID" ]; then
    # Get lines: Product Name, Movement Qty
    # M_ProductionLine maps to M_Product
    LINES_DATA=$(idempiere_query "
    SELECT pr.name, pl.movementqty
    FROM m_productionline pl
    JOIN m_product pr ON pl.m_product_id = pr.m_product_id
    WHERE pl.m_production_id = $PROD_ID
    " 2>/dev/null)
    
    # Convert PSQL output to JSON array
    # Output format: Name|Qty (one per line)
    LINES_JSON=$(echo "$LINES_DATA" | python3 -c '
import sys, json
lines = []
for row in sys.stdin:
    row = row.strip()
    if row:
        parts = row.split("|")
        if len(parts) >= 2:
            lines.append({"product": parts[0], "qty": parts[1]})
print(json.dumps(lines))
')
fi

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "record_found": $FOUND,
    "production_id": "$PROD_ID",
    "production_name": "$PROD_NAME",
    "production_qty": "$PROD_QTY",
    "product_name": "$PRODUCT_NAME",
    "created_at": "$CREATED",
    "lines": $LINES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to shared location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json