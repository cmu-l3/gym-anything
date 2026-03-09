#!/bin/bash
# Export script for Implement Staff Picks task
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load Target IDs
if [ -f /tmp/target_ids.json ]; then
    SONY_ID=$(grep -o '"sony_id": "[^"]*"' /tmp/target_ids.json | cut -d'"' -f4)
    LOGI_ID=$(grep -o '"logitech_id": "[^"]*"' /tmp/target_ids.json | cut -d'"' -f4)
else
    # Fallback lookup
    SONY_ID=$(get_product_id_by_title "Sony WH-1000XM5 Wireless Headphones" 2>/dev/null)
    LOGI_ID=$(get_product_id_by_title "Logitech MX Master 3S Wireless Mouse" 2>/dev/null)
fi

# ======================================================
# 1. Verify Field Existence
# ======================================================
FIELD_EXISTS="false"
# Check config table for the field storage definition
FIELD_CONFIG_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.commerce_product.field_staff_pick'" 2>/dev/null || echo "0")
if [ "$FIELD_CONFIG_COUNT" -gt 0 ]; then
    FIELD_EXISTS="true"
fi

# ======================================================
# 2. Verify Data Values (Content Curation)
# ======================================================
SONY_TAGGED="false"
LOGI_TAGGED="false"
FALSE_POSITIVES="0"

if [ "$FIELD_EXISTS" = "true" ]; then
    # Check Sony
    SONY_VAL=$(drupal_db_query "SELECT field_staff_pick_value FROM commerce_product__field_staff_pick WHERE entity_id = '$SONY_ID'" 2>/dev/null || echo "")
    if [ "$SONY_VAL" = "1" ]; then SONY_TAGGED="true"; fi

    # Check Logitech
    LOGI_VAL=$(drupal_db_query "SELECT field_staff_pick_value FROM commerce_product__field_staff_pick WHERE entity_id = '$LOGI_ID'" 2>/dev/null || echo "")
    if [ "$LOGI_VAL" = "1" ]; then LOGI_TAGGED="true"; fi

    # Check for other products accidentally tagged
    FALSE_POSITIVES=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__field_staff_pick WHERE field_staff_pick_value = 1 AND entity_id NOT IN ('$SONY_ID', '$LOGI_ID')" 2>/dev/null || echo "0")
fi

# ======================================================
# 3. Verify View Configuration
# ======================================================
VIEW_EXISTS="false"
VIEW_HAS_FILTER="false"
VIEW_DISPLAY_BLOCK="false"

# List views looking for 'staff_picks'
VIEW_CONFIG=$(drupal_db_query "SELECT data FROM config WHERE name LIKE 'views.view.staff_picks%' LIMIT 1" 2>/dev/null)

if [ -n "$VIEW_CONFIG" ]; then
    VIEW_EXISTS="true"
    # Crude check inside the serialized/blob data for the field name in filters
    if echo "$VIEW_CONFIG" | grep -q "field_staff_pick"; then
        VIEW_HAS_FILTER="true"
    fi
    # Check for block display plugin
    if echo "$VIEW_CONFIG" | grep -q "block"; then
        VIEW_DISPLAY_BLOCK="true"
    fi
fi

# ======================================================
# 4. Verify Block Placement
# ======================================================
BLOCK_PLACED="false"
BLOCK_REGION=""

# Check active block instances. The plugin ID for a view block usually follows 'views_block:view_name-display_id'
# We look for something related to 'staff_picks'
BLOCK_DATA=$(drupal_db_query "SELECT region, theme FROM config WHERE name LIKE 'block.block.%' AND data LIKE '%views_block:staff_picks%' LIMIT 1" 2>/dev/null)

if [ -n "$BLOCK_DATA" ]; then
    BLOCK_PLACED="true"
    BLOCK_REGION=$(echo "$BLOCK_DATA" | awk '{print $1}') # Just simplistic extraction
fi

# ======================================================
# 5. Verify Frontend Visibility (HTML Check)
# ======================================================
# Fetch the homepage
curl -s http://localhost/ > /tmp/homepage.html

# Check if our target strings are present in the HTML
HTML_CONTAINS_TITLE="false"
HTML_CONTAINS_SONY="false"
HTML_CONTAINS_LOGI="false"

if grep -iq "Staff Picks" /tmp/homepage.html; then HTML_CONTAINS_TITLE="true"; fi
if grep -iq "Sony WH-1000XM5" /tmp/homepage.html; then HTML_CONTAINS_SONY="true"; fi
if grep -iq "Logitech MX Master 3S" /tmp/homepage.html; then HTML_CONTAINS_LOGI="true"; fi

# ======================================================
# Build Result JSON
# ======================================================
create_result_json /tmp/task_result.json \
    "field_exists=$FIELD_EXISTS" \
    "sony_tagged=$SONY_TAGGED" \
    "logi_tagged=$LOGI_TAGGED" \
    "false_positives=$FALSE_POSITIVES" \
    "view_exists=$VIEW_EXISTS" \
    "view_has_filter=$VIEW_HAS_FILTER" \
    "view_display_block=$VIEW_DISPLAY_BLOCK" \
    "block_placed=$BLOCK_PLACED" \
    "block_region=$(json_escape "$BLOCK_REGION")" \
    "html_contains_title=$HTML_CONTAINS_TITLE" \
    "html_contains_sony=$HTML_CONTAINS_SONY" \
    "html_contains_logi=$HTML_CONTAINS_LOGI"

chmod 666 /tmp/task_result.json

# Copy HTML for verifier (optional, but good for debugging if needed)
cp /tmp/homepage.html /tmp/task_homepage.html
chmod 666 /tmp/task_homepage.html

echo "Export complete."
cat /tmp/task_result.json