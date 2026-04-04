#!/bin/bash
# Export script for configure_store_pages task
echo "=== Exporting configure_store_pages Result ==="

source /workspace/scripts/task_utils.sh

# Helper for JSON escaping
json_escape_str() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g' | tr -d '\r'
}

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Get Drush configuration (System Site Info)
cd /var/www/html/drupal
DRUSH="vendor/bin/drush"

SITE_NAME=$($DRUSH config:get system.site name --format=string 2>/dev/null)
SITE_SLOGAN=$($DRUSH config:get system.site slogan --format=string 2>/dev/null)
FRONT_PAGE=$($DRUSH config:get system.site page.front --format=string 2>/dev/null)

# 3. Check Pages (Nodes)
# We look for nodes created during the session or by title
# Return Policy
RETURN_NODE_ID=$(drupal_db_query "SELECT nid FROM node_field_data WHERE title='Return Policy' ORDER BY nid DESC LIMIT 1")
RETURN_BODY=""
RETURN_ALIAS=""
RETURN_STATUS="0"

if [ -n "$RETURN_NODE_ID" ]; then
    RETURN_STATUS=$(drupal_db_query "SELECT status FROM node_field_data WHERE nid=$RETURN_NODE_ID")
    RETURN_BODY=$(drupal_db_query "SELECT body_value FROM node__body WHERE entity_id=$RETURN_NODE_ID")
    # Check alias
    RETURN_ALIAS=$(drupal_db_query "SELECT alias FROM path_alias WHERE path='/node/$RETURN_NODE_ID' LIMIT 1")
fi

# Shipping Info
SHIPPING_NODE_ID=$(drupal_db_query "SELECT nid FROM node_field_data WHERE title='Shipping Information' ORDER BY nid DESC LIMIT 1")
SHIPPING_BODY=""
SHIPPING_ALIAS=""
SHIPPING_STATUS="0"

if [ -n "$SHIPPING_NODE_ID" ]; then
    SHIPPING_STATUS=$(drupal_db_query "SELECT status FROM node_field_data WHERE nid=$SHIPPING_NODE_ID")
    SHIPPING_BODY=$(drupal_db_query "SELECT body_value FROM node__body WHERE entity_id=$SHIPPING_NODE_ID")
    SHIPPING_ALIAS=$(drupal_db_query "SELECT alias FROM path_alias WHERE path='/node/$SHIPPING_NODE_ID' LIMIT 1")
fi

# 4. Check Menu Links
# Get all enabled links in 'main' menu
MENU_LINKS_JSON=$(drupal_db_query "SELECT title, link__uri FROM menu_link_content_data WHERE menu_name='main' AND enabled=1" | \
    python3 -c "
import sys, json, csv
reader = csv.reader(sys.stdin, delimiter='\t')
links = []
for row in reader:
    if len(row) >= 2:
        links.append({'title': row[0], 'uri': row[1]})
print(json.dumps(links))
")

# 5. Anti-gaming / Change detection
INITIAL_NODE_COUNT=$(cat /tmp/initial_node_count.txt 2>/dev/null || echo "0")
CURRENT_NODE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM node_field_data")

INITIAL_MENU_COUNT=$(cat /tmp/initial_menu_link_count.txt 2>/dev/null || echo "0")
CURRENT_MENU_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM menu_link_content_data")

# 6. Build Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "site_config": {
        "name": "$(json_escape_str "$SITE_NAME")",
        "slogan": "$(json_escape_str "$SITE_SLOGAN")",
        "front_page": "$(json_escape_str "$FRONT_PAGE")"
    },
    "pages": {
        "return_policy": {
            "exists": $([ -n "$RETURN_NODE_ID" ] && echo "true" || echo "false"),
            "status": ${RETURN_STATUS:-0},
            "alias": "$(json_escape_str "$RETURN_ALIAS")",
            "body_snippet": "$(json_escape_str "${RETURN_BODY:0:200}")..."
        },
        "shipping_info": {
            "exists": $([ -n "$SHIPPING_NODE_ID" ] && echo "true" || echo "false"),
            "status": ${SHIPPING_STATUS:-0},
            "alias": "$(json_escape_str "$SHIPPING_ALIAS")",
            "body_snippet": "$(json_escape_str "${SHIPPING_BODY:0:200}")..."
        }
    },
    "menu_links": ${MENU_LINKS_JSON:-[]},
    "stats": {
        "initial_node_count": $INITIAL_NODE_COUNT,
        "current_node_count": ${CURRENT_NODE_COUNT:-0},
        "initial_menu_count": $INITIAL_MENU_COUNT,
        "current_menu_count": ${CURRENT_MENU_COUNT:-0}
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="