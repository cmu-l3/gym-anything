#!/bin/bash
# Export script for Support Ticket System task
echo "=== Exporting implement_support_ticket_system Result ==="

source /workspace/scripts/task_utils.sh

# Helper to run DB queries safely
query_db() {
    drupal_db_query "$1" 2>/dev/null
}

# 1. Capture Final Screenshot (Evidence of View or Node)
take_screenshot /tmp/task_final.png

# 2. Verify Content Type ('support_ticket')
# Check node_type table
CT_EXISTS=$(query_db "SELECT COUNT(*) FROM node_type WHERE type = 'support_ticket'")
CT_EXISTS=${CT_EXISTS:-0}

# 3. Verify Fields
# We look for field config in the config table or specific tables.
# A robust way is checking the 'config' table for storage definitions.

# Check for Order Reference Field
# Look for a field storage config that targets 'commerce_order'
# The config name format is usually field.storage.node.field_name
ORDER_FIELD_FOUND="false"
ORDER_FIELD_NAME=""
# We search for any config that is a field storage for nodes and has type entity_reference targeting commerce_order
# This requires parsing the serialized blob or YAML, simplified here by grep on the config data
ORDER_FIELD_CONFIG=$(query_db "SELECT name, data FROM config WHERE name LIKE 'field.storage.node.%'")
if echo "$ORDER_FIELD_CONFIG" | grep -q "commerce_order"; then
    ORDER_FIELD_FOUND="true"
    # Extract field name roughly
    ORDER_FIELD_NAME=$(echo "$ORDER_FIELD_CONFIG" | grep "commerce_order" | head -n 1 | awk '{print $1}' | sed 's/field.storage.node.//')
fi

# Check for Priority Field (List)
# Look for field storage with allowed values Low, Normal, High, Critical
PRIORITY_FIELD_FOUND="false"
PRIORITY_FIELD_NAME=""
if echo "$ORDER_FIELD_CONFIG" | grep -q "Critical"; then
    PRIORITY_FIELD_FOUND="true"
    PRIORITY_FIELD_NAME=$(echo "$ORDER_FIELD_CONFIG" | grep "Critical" | head -n 1 | awk '{print $1}' | sed 's/field.storage.node.//')
fi

# 4. Verify Test Node
# Look for node with title 'Defective Battery' of type 'support_ticket'
NODE_DATA=$(query_db "SELECT nid FROM node_field_data WHERE type = 'support_ticket' AND title = 'Defective Battery' LIMIT 1")
NODE_FOUND="false"
NODE_ID=""
NODE_HAS_ORDER="false"
NODE_PRIORITY_VAL=""

if [ -n "$NODE_DATA" ]; then
    NODE_FOUND="true"
    NODE_ID=$NODE_DATA
    
    # Check Order Link
    # If field name was found, check the specific table node__field_name
    if [ -n "$ORDER_FIELD_NAME" ]; then
        TABLE_NAME="node__$ORDER_FIELD_NAME"
        COL_NAME="${ORDER_FIELD_NAME}_target_id"
        LINKED_ORDER=$(query_db "SELECT $COL_NAME FROM $TABLE_NAME WHERE entity_id = $NODE_ID")
        if [ -n "$LINKED_ORDER" ]; then
            NODE_HAS_ORDER="true"
        fi
    fi

    # Check Priority Value
    if [ -n "$PRIORITY_FIELD_NAME" ]; then
        TABLE_NAME="node__$PRIORITY_FIELD_NAME"
        COL_NAME="${PRIORITY_FIELD_NAME}_value"
        # We expect 'High' (or key 2 depending on how they set it up, but usually value match)
        PRIORITY_VAL=$(query_db "SELECT $COL_NAME FROM $TABLE_NAME WHERE entity_id = $NODE_ID")
        NODE_PRIORITY_VAL=$PRIORITY_VAL
    fi
fi

# 5. Verify View
# Check if a view exists with path '/admin/support-tickets'
# The 'router' table contains paths registered by Views
ROUTER_CHECK=$(query_db "SELECT name FROM router WHERE path = '/admin/support-tickets'")
VIEW_PATH_EXISTS="false"
if [ -n "$ROUTER_CHECK" ]; then
    VIEW_PATH_EXISTS="true"
fi

# Check View Config for exposed filter (grep config)
VIEW_CONFIG=$(query_db "SELECT data FROM config WHERE name LIKE 'views.view.%' AND data LIKE '%/admin/support-tickets%'")
HAS_EXPOSED_FILTER="false"
if echo "$VIEW_CONFIG" | grep -q "exposed.: true"; then
    HAS_EXPOSED_FILTER="true"
fi
# Alternative check for priority filter specifically
if echo "$VIEW_CONFIG" | grep -q "priority"; then
    HAS_PRIORITY_FILTER="true" # Weak check, but acceptable combined with others
else
    HAS_PRIORITY_FILTER="false"
fi

# 6. Anti-Gaming Timestamp Check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# We can check the 'created' timestamp of the node
NODE_CREATED_TS=0
if [ -n "$NODE_ID" ]; then
    NODE_CREATED_TS=$(query_db "SELECT created FROM node_field_data WHERE nid = $NODE_ID")
fi

CREATED_DURING_TASK="false"
if [ "$NODE_CREATED_TS" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# 7. Generate JSON
cat > /tmp/task_result.json << EOF
{
    "content_type_exists": $( [ "$CT_EXISTS" -gt 0 ] && echo "true" || echo "false" ),
    "order_field_found": $ORDER_FIELD_FOUND,
    "priority_field_found": $PRIORITY_FIELD_FOUND,
    "node_found": $NODE_FOUND,
    "node_has_order": $NODE_HAS_ORDER,
    "node_priority_value": "$(echo "$NODE_PRIORITY_VAL" | tr -d '\n')",
    "view_path_exists": $VIEW_PATH_EXISTS,
    "view_has_exposed_filter": $HAS_EXPOSED_FILTER,
    "node_created_during_task": $CREATED_DURING_TASK
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="