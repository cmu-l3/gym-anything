#!/bin/bash
echo "=== Exporting configure_linked_products result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get IDs again for verification logic
TARGET_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='USBC-065' AND p.post_type='product' LIMIT 1")
UPSELL_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='WBH-001' AND p.post_type='product' LIMIT 1")
CROSS1_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='OCT-BLK-M' AND p.post_type='product' LIMIT 1")
CROSS2_ID=$(wc_query "SELECT p.ID FROM wp_posts p JOIN wp_postmeta pm ON p.ID = pm.post_id WHERE pm.meta_key='_sku' AND pm.meta_value='SFDJ-BLU-32' AND p.post_type='product' LIMIT 1")

# Get Product Modification Time
POST_MODIFIED_TS="0"
if [ -n "$TARGET_ID" ]; then
    POST_MODIFIED=$(wc_query "SELECT post_modified_gmt FROM wp_posts WHERE ID=$TARGET_ID")
    if [ -n "$POST_MODIFIED" ]; then
        POST_MODIFIED_TS=$(date -d "$POST_MODIFIED" +%s 2>/dev/null || echo "0")
    fi
fi

# Get Linked Products Metadata
# We use WP-CLI to get the data as JSON to avoid parsing serialized PHP arrays manually
cd /var/www/html/wordpress
UPSELL_IDS_JSON="[]"
CROSSSELL_IDS_JSON="[]"

if [ -n "$TARGET_ID" ]; then
    # wp post meta get returns serialized data decoded if we don't ask for specific format, 
    # but with --format=json it handles array structures nicely.
    # Note: WooCommerce stores these as serialized arrays. WP-CLI handles unserialization.
    UPSELL_IDS_JSON=$(wp post meta get "$TARGET_ID" _upsell_ids --format=json --allow-root 2>/dev/null || echo "[]")
    CROSSSELL_IDS_JSON=$(wp post meta get "$TARGET_ID" _crosssell_ids --format=json --allow-root 2>/dev/null || echo "[]")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_id": "${TARGET_ID:-0}",
    "target_exists": $([ -n "$TARGET_ID" ] && echo "true" || echo "false"),
    "post_modified_ts": $POST_MODIFIED_TS,
    "upsell_ids": $UPSELL_IDS_JSON,
    "crosssell_ids": $CROSSSELL_IDS_JSON,
    "expected_upsell_id": "${UPSELL_ID:-0}",
    "expected_cross1_id": "${CROSS1_ID:-0}",
    "expected_cross2_id": "${CROSS2_ID:-0}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="