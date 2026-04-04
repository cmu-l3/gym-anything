#!/bin/bash
# Export script for Configure Store Shipping task
echo "=== Exporting Configure Store Shipping Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Standard Ground Shipping Data
# Search by name pattern
STANDARD_DATA=$(drupal_db_query "SELECT shipping_method_id, name, status, plugin__target_plugin_configuration FROM commerce_shipping_method_field_data WHERE name LIKE '%Standard%Ground%' ORDER BY shipping_method_id DESC LIMIT 1")

STD_FOUND="false"
STD_ID=""
STD_NAME=""
STD_STATUS=""
STD_RATE=""
STD_STORE_ASSIGNED="false"

if [ -n "$STANDARD_DATA" ]; then
    STD_FOUND="true"
    STD_ID=$(echo "$STANDARD_DATA" | cut -f1)
    STD_NAME=$(echo "$STANDARD_DATA" | cut -f2)
    STD_STATUS=$(echo "$STANDARD_DATA" | cut -f3)
    # Configuration is the 4th field, possibly containing tabs/newlines, so we extract carefully
    # Re-query just the config to be safe
    STD_CONFIG=$(drupal_db_query "SELECT CAST(plugin__target_plugin_configuration AS CHAR) FROM commerce_shipping_method_field_data WHERE shipping_method_id = $STD_ID")
    
    # Extract rate amount using Python regex
    STD_RATE=$(echo "$STD_CONFIG" | python3 -c "
import sys, re
data = sys.stdin.read()
# Serialized pattern: s:6:\"number\";s:4:\"7.99\"
m = re.search(r'\"number\";s:\d+:\"([0-9.]+)\"', data)
if m:
    print(m.group(1))
else:
    # Fallback/loose match
    m2 = re.search(r'number.*?([0-9.]+)', data)
    print(m2.group(1) if m2 else '0')
")

    # Check store assignment
    STORE_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_shipping_method__stores WHERE entity_id = $STD_ID AND stores_target_id = 1")
    if [ "$STORE_CHECK" -gt "0" ] 2>/dev/null; then
        STD_STORE_ASSIGNED="true"
    fi
fi

# 2. Get Express Overnight Shipping Data
EXPRESS_DATA=$(drupal_db_query "SELECT shipping_method_id, name, status FROM commerce_shipping_method_field_data WHERE name LIKE '%Express%Overnight%' ORDER BY shipping_method_id DESC LIMIT 1")

EXP_FOUND="false"
EXP_ID=""
EXP_NAME=""
EXP_STATUS=""
EXP_RATE=""
EXP_STORE_ASSIGNED="false"

if [ -n "$EXPRESS_DATA" ]; then
    EXP_FOUND="true"
    EXP_ID=$(echo "$EXPRESS_DATA" | cut -f1)
    EXP_NAME=$(echo "$EXPRESS_DATA" | cut -f2)
    EXP_STATUS=$(echo "$EXPRESS_DATA" | cut -f3)
    
    EXP_CONFIG=$(drupal_db_query "SELECT CAST(plugin__target_plugin_configuration AS CHAR) FROM commerce_shipping_method_field_data WHERE shipping_method_id = $EXP_ID")
    
    EXP_RATE=$(echo "$EXP_CONFIG" | python3 -c "
import sys, re
data = sys.stdin.read()
m = re.search(r'\"number\";s:\d+:\"([0-9.]+)\"', data)
if m:
    print(m.group(1))
else:
    m2 = re.search(r'number.*?([0-9.]+)', data)
    print(m2.group(1) if m2 else '0')
")

    STORE_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_shipping_method__stores WHERE entity_id = $EXP_ID AND stores_target_id = 1")
    if [ "$STORE_CHECK" -gt "0" ] 2>/dev/null; then
        EXP_STORE_ASSIGNED="true"
    fi
fi

# 3. Counts and Timestamps
INITIAL_COUNT=$(cat /tmp/initial_shipping_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_shipping_method_field_data")
CURRENT_COUNT=${CURRENT_COUNT:-0}

# JSON Export
cat > /tmp/task_result.json << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "standard": {
        "found": $STD_FOUND,
        "name": "$(json_escape "$STD_NAME")",
        "status": "${STD_STATUS:-0}",
        "rate": "${STD_RATE:-0}",
        "store_assigned": $STD_STORE_ASSIGNED
    },
    "express": {
        "found": $EXP_FOUND,
        "name": "$(json_escape "$EXP_NAME")",
        "status": "${EXP_STATUS:-0}",
        "rate": "${EXP_RATE:-0}",
        "store_assigned": $EXP_STORE_ASSIGNED
    }
}
EOF

# Ensure readable
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="