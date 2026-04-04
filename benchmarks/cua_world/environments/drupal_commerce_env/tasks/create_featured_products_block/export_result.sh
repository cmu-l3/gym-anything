#!/bin/bash
# Export script for Create Featured Products Block task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Product Data (Database)
# We need to verify specific products are promoted
echo "Checking product statuses..."

# Helper to check promotion status by title partial match
check_promote() {
    local title="$1"
    # Escaping for SQL
    local sql_title=$(echo "$title" | sed "s/'/\\\\'/g")
    local status=$(drupal_db_query "SELECT promote FROM commerce_product_field_data WHERE title LIKE '%$sql_title%' LIMIT 1" 2>/dev/null)
    echo "${status:-0}"
}

SONY_STATUS=$(check_promote "Sony WH-1000XM5")
APPLE_STATUS=$(check_promote "Apple MacBook Pro")
CANON_STATUS=$(check_promote "Canon EOS R6")
LOGI_STATUS=$(check_promote "Logitech MX Master") # Should be 0

# 3. Check View Configuration (Drush)
echo "Checking View configuration..."
VIEW_ID="staff_picks"
VIEW_CONFIG_FILE="/tmp/view_config.json"

# Export view config to JSON
drush_cmd config:get "views.view.$VIEW_ID" --format=json > "$VIEW_CONFIG_FILE" 2>/dev/null

VIEW_EXISTS="false"
if [ -s "$VIEW_CONFIG_FILE" ]; then
    VIEW_EXISTS="true"
fi

# 4. Check Block Placement (Drush)
echo "Checking Block placement..."
# Find the block config name (it might be views_block__staff_picks_block_1 or similar)
# We search for any block config that depends on the view
BLOCK_CONFIG_NAME=$(drush_cmd config:list | grep "block.block.views_block__$VIEW_ID" | head -n 1)
BLOCK_CONFIG_FILE="/tmp/block_config.json"

BLOCK_EXISTS="false"
if [ -n "$BLOCK_CONFIG_NAME" ]; then
    drush_cmd config:get "$BLOCK_CONFIG_NAME" --format=json > "$BLOCK_CONFIG_FILE" 2>/dev/null
    if [ -s "$BLOCK_CONFIG_FILE" ]; then
        BLOCK_EXISTS="true"
    fi
else
    echo "{}" > "$BLOCK_CONFIG_FILE"
fi

# 5. Anti-gaming / Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create consolidated JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "product_data": {
        "sony_promoted": $SONY_STATUS,
        "apple_promoted": $APPLE_STATUS,
        "canon_promoted": $CANON_STATUS,
        "logi_promoted": $LOGI_STATUS
    },
    "view_exists": $VIEW_EXISTS,
    "block_exists": $BLOCK_EXISTS,
    "block_config_name": "$BLOCK_CONFIG_NAME"
}
EOF

# Move files to accessible location for copy_from_env
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/view_config.json 2>/dev/null || true
chmod 666 /tmp/block_config.json 2>/dev/null || true

rm "$TEMP_JSON"

echo "=== Export Complete ==="