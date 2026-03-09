#!/bin/bash
# Export script for create_promo_banner_block task
echo "=== Exporting create_promo_banner_block Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify Block Type Existence
# Check config table for 'block_content.type.promo_banner'
BLOCK_TYPE_EXISTS="false"
BT_CHECK=$(drupal_db_query "SELECT name FROM config WHERE name = 'block_content.type.promo_banner'")
if [ -n "$BT_CHECK" ]; then
    BLOCK_TYPE_EXISTS="true"
fi

# 2. Verify Fields Existence
FIELD_LINK_EXISTS="false"
FL_CHECK=$(drupal_db_query "SELECT name FROM config WHERE name = 'field.storage.block_content.field_promo_link'")
if [ -n "$FL_CHECK" ]; then
    FIELD_LINK_EXISTS="true"
fi

FIELD_COUPON_EXISTS="false"
FC_CHECK=$(drupal_db_query "SELECT name FROM config WHERE name = 'field.storage.block_content.field_coupon_code'")
if [ -n "$FC_CHECK" ]; then
    FIELD_COUPON_EXISTS="true"
fi

# 3. Verify Block Content
# Look for block with description "Summer Audio Sale"
EXPECTED_DESC="Summer Audio Sale"
BLOCK_FOUND="false"
BLOCK_ID=""
BLOCK_UUID=""
COUPON_VALUE=""
LINK_URI=""

# Find block ID by description
BLOCK_DATA=$(drupal_db_query "SELECT id, uuid FROM block_content_field_data WHERE info LIKE '%$EXPECTED_DESC%' ORDER BY id DESC LIMIT 1")

if [ -n "$BLOCK_DATA" ]; then
    BLOCK_FOUND="true"
    BLOCK_ID=$(echo "$BLOCK_DATA" | cut -f1)
    BLOCK_UUID=$(echo "$BLOCK_DATA" | cut -f2)
    
    # Get Coupon Value
    # Table name pattern: block_content__field_coupon_code
    # Column pattern: field_coupon_code_value
    # Use python to safely query or just raw SQL if table exists
    
    # Check if table exists first to avoid SQL error
    TABLE_CHECK=$(drupal_db_query "SHOW TABLES LIKE 'block_content__field_coupon_code'")
    if [ -n "$TABLE_CHECK" ]; then
        COUPON_VALUE=$(drupal_db_query "SELECT field_coupon_code_value FROM block_content__field_coupon_code WHERE entity_id = $BLOCK_ID")
    fi

    # Get Link URI
    TABLE_CHECK_LINK=$(drupal_db_query "SHOW TABLES LIKE 'block_content__field_promo_link'")
    if [ -n "$TABLE_CHECK_LINK" ]; then
        LINK_URI=$(drupal_db_query "SELECT field_promo_link_uri FROM block_content__field_promo_link WHERE entity_id = $BLOCK_ID")
    fi
fi

# 4. Verify Placement
# This is tricky because config data is serialized PHP.
# We need to find a config entry in 'block.block.%' that:
# - Is for the olivero theme (usually)
# - Has 'region' => 'sidebar' (or sidebar_first)
# - Has 'plugin' => 'block_content:UUID'
PLACEMENT_FOUND="false"
PLACEMENT_REGION=""

if [ -n "$BLOCK_UUID" ]; then
    # We use a python script to parse the config table to find the placement
    # We select name and data from config where name starts with block.block.
    
    # Export relevant config to a temp file
    drupal_db_query "SELECT name, CAST(data AS CHAR) FROM config WHERE name LIKE 'block.block.%'" > /tmp/block_config_dump.txt
    
    # Python script to parse
    cat > /tmp/parse_placement.py << PYEOF
import sys
import re

block_uuid = "$BLOCK_UUID"
target_regions = ["sidebar", "sidebar_first", "sidebar_second"]

found = False
region = ""

# Read from file
try:
    with open('/tmp/block_config_dump.txt', 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        
    for line in lines:
        # Very rough parsing because the dump format from mysql -e might be tab separated
        if block_uuid in line:
            # This config references our block. Now check region.
            # PHP serialized string: s:6:"region";s:7:"sidebar";
            # or simply look for region assignment
            
            # Simple regex check for region
            # We look for "region";s:N:"REGION_NAME"
            match = re.search(r's:6:"region";s:\d+:"([^"]+)"', line)
            if match:
                r = match.group(1)
                if r in target_regions or "sidebar" in r:
                    found = True
                    region = r
                    break
            
            # Fallback: check if 'sidebar' appears near 'region'
            if "region" in line and "sidebar" in line:
                # Heuristic check
                found = True
                region = "sidebar_detected"
                break

    print(f"{found}|{region}")
except Exception as e:
    print(f"False|Error: {e}")
PYEOF

    PARSE_RESULT=$(python3 /tmp/parse_placement.py)
    PLACEMENT_FOUND=$(echo "$PARSE_RESULT" | cut -d'|' -f1)
    PLACEMENT_REGION=$(echo "$PARSE_RESULT" | cut -d'|' -f2)
fi

# Generate JSON result
create_result_json /tmp/task_result.json \
    "block_type_exists=$BLOCK_TYPE_EXISTS" \
    "field_link_exists=$FIELD_LINK_EXISTS" \
    "field_coupon_exists=$FIELD_COUPON_EXISTS" \
    "block_found=$BLOCK_FOUND" \
    "block_desc=$(json_escape "$EXPECTED_DESC")" \
    "coupon_value=$(json_escape "$COUPON_VALUE")" \
    "link_uri=$(json_escape "$LINK_URI")" \
    "placement_found=$PLACEMENT_FOUND" \
    "placement_region=$(json_escape "$PLACEMENT_REGION")"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="