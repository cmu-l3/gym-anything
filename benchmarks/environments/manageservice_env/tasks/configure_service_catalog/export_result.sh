#!/bin/bash
# Export results for configure_service_catalog task
set -e

echo "=== Exporting Service Catalog Configuration ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Specific Records
# We look for the Category and the Item by Name

# Query ServiceCategory
# Note: Table names in SDP Postgres are usually lowercase or CamelCase depending on version.
# usage: sdp_db_exec "SQL"
CAT_QUERY="SELECT name, description FROM ServiceCategory WHERE name = 'Hardware Services';"
CAT_RESULT=$(sdp_db_exec "$CAT_QUERY")

# Query ServiceDefinition (Items)
# We also want to check the relation, but finding the item by name is the primary check.
ITEM_QUERY="SELECT name, description FROM ServiceDefinition WHERE name = 'New Laptop Request';"
ITEM_RESULT=$(sdp_db_exec "$ITEM_QUERY")

# Get Counts again
FINAL_CAT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM ServiceCategory" 2>/dev/null || echo "0")
FINAL_ITEM_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM ServiceDefinition" 2>/dev/null || echo "0")
INITIAL_CAT_COUNT=$(cat /tmp/initial_category_count.txt 2>/dev/null || echo "0")
INITIAL_ITEM_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

try:
    cat_res = '''$CAT_RESULT'''
    item_res = '''$ITEM_RESULT'''
    
    # Parse Category Result (Expect: Hardware Services|Description...)
    cat_found = False
    cat_desc = ''
    if 'Hardware Services' in cat_res:
        cat_found = True
        cat_desc = cat_res
        
    # Parse Item Result
    item_found = False
    item_desc = ''
    if 'New Laptop Request' in item_res:
        item_found = True
        item_desc = item_res

    result = {
        'category_found': cat_found,
        'category_details': cat_desc.strip(),
        'item_found': item_found,
        'item_details': item_desc.strip(),
        'counts': {
            'initial_cat': int('$INITIAL_CAT_COUNT'),
            'final_cat': int('$FINAL_CAT_COUNT'),
            'initial_item': int('$INITIAL_ITEM_COUNT'),
            'final_item': int('$FINAL_ITEM_COUNT')
        },
        'screenshot_exists': True
    }
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json