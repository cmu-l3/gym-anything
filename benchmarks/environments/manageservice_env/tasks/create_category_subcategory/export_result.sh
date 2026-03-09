#!/bin/bash
# Export script for create_category_subcategory task
# Queries the SDP database to verify the category structure

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check if Category "Cloud Services" exists
# We use LOWER() for case-insensitive verification, though exact match is preferred
log "Checking for 'Cloud Services' category..."
CAT_INFO=$(sdp_db_exec "SELECT categoryid, name FROM categorydefinition WHERE LOWER(name) = 'cloud services' LIMIT 1;" "servicedesk")

CAT_ID=""
CAT_NAME=""
CAT_EXISTS="false"

if [ -n "$CAT_INFO" ]; then
    # Parse the result (psql output might need cleaning)
    CAT_ID=$(echo "$CAT_INFO" | cut -d'|' -f1 | tr -d '[:space:]')
    CAT_NAME=$(echo "$CAT_INFO" | cut -d'|' -f2)
    
    if [ -n "$CAT_ID" ]; then
        CAT_EXISTS="true"
        log "Found Category: ID=$CAT_ID, Name=$CAT_NAME"
    fi
fi

# 2. Check for Subcategories linked to this Category
SUBCATS_JSON="[]"

if [ "$CAT_EXISTS" = "true" ]; then
    # Fetch all subcategories for this category ID
    # Constructing a JSON array of names manually using psql iteration is tricky, 
    # so we'll just get the raw list and format it.
    
    RAW_SUBCATS=$(sdp_db_exec "SELECT name FROM subcategorydefinition WHERE categoryid = $CAT_ID;" "servicedesk")
    
    # Convert newline separated list to JSON array
    # Example raw: 
    # Provisioning
    # Access Management
    
    if [ -n "$RAW_SUBCATS" ]; then
        SUBCATS_JSON=$(echo "$RAW_SUBCATS" | python3 -c '
import sys, json
lines = [l.strip() for l in sys.stdin.readlines() if l.strip()]
print(json.dumps(lines))
')
    fi
    log "Found Subcategories: $SUBCATS_JSON"
fi

# 3. Get total counts for anti-gaming
FINAL_CAT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM categorydefinition;" 2>/dev/null || echo "0")
INITIAL_CAT_COUNT=$(cat /tmp/initial_cat_count.txt 2>/dev/null || echo "0")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "category_exists": $CAT_EXISTS,
    "category_id": "${CAT_ID:-0}",
    "category_name": "${CAT_NAME:-}",
    "subcategories_found": $SUBCATS_JSON,
    "initial_cat_count": ${INITIAL_CAT_COUNT:-0},
    "final_cat_count": ${FINAL_CAT_COUNT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="