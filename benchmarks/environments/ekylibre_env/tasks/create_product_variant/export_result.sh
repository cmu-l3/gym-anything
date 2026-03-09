#!/bin/bash
# Export script for create_product_variant task
# Verifies database state and captures evidence

set -e
echo "=== Exporting create_product_variant results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_variant_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM product_nature_variants")

# 3. Search for the specific created record
# We look for the name 'Ammonitrate 33.5'
# We also retrieve the associated Nature ID to verify it's linked correctly
RECORD_JSON=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "
    SELECT row_to_json(t) FROM (
        SELECT id, name, product_nature_id, created_at, updated_at 
        FROM product_nature_variants 
        WHERE name ILIKE '%Ammonitrate 33.5%' 
        ORDER BY created_at DESC 
        LIMIT 1
    ) t;
" 2>/dev/null || echo "")

# 4. Check if a record was actually found
RECORD_FOUND="false"
if [ -n "$RECORD_JSON" ]; then
    RECORD_FOUND="true"
fi

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "record_found": $RECORD_FOUND,
    "record_details": ${RECORD_JSON:-null},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to standard output location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="