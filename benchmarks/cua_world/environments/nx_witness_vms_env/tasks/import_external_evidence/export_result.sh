#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Data via API
# We need to verify:
# - Layout "Case #4492-Investigation" exists
# - It contains 2 items
# - The items refer to resources named "Exhibit A..." and "Exhibit B..."

refresh_nx_token > /dev/null 2>&1 || true

# Get all layouts
echo "Fetching layouts..."
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts")

# Get all resources (includes cameras AND local files usually)
# Note: In some Nx versions, local files appear in /rest/v1/resources or /rest/v1/devices
# We'll fetch both generic devices and specific resources if available.
echo "Fetching resources..."
RESOURCES_JSON=$(nx_api_get "/rest/v1/devices") 
# Try alternate endpoint for media server resources if devices doesn't have them
RESOURCES_EXTRA=$(nx_api_get "/rest/v1/mediaServers" 2>/dev/null || echo "[]")

# 3. Construct Result JSON
# We use Python to parse the messy API responses and produce a clean verification file
python3 -c "
import json
import os
import sys

try:
    layouts = json.loads('$LAYOUTS_JSON')
    resources = json.loads('$RESOURCES_JSON')
    
    target_layout_name = 'Case #4492-Investigation'
    target_layout = None
    
    # Find the specific layout
    for l in layouts:
        if l.get('name', '') == target_layout_name:
            target_layout = l
            break
            
    # Map resource IDs to Names
    resource_map = {}
    for r in resources:
        rid = r.get('id')
        rname = r.get('name')
        if rid:
            resource_map[rid] = rname
            
    # Analyze layout items
    layout_items_data = []
    if target_layout and 'items' in target_layout:
        for item in target_layout['items']:
            rid = item.get('resourceId')
            name = resource_map.get(rid, 'Unknown')
            layout_items_data.append({
                'resourceId': rid,
                'name': name
            })

    result = {
        'layout_found': target_layout is not None,
        'layout_name': target_layout_name,
        'layout_item_count': len(layout_items_data),
        'layout_items': layout_items_data,
        'all_resource_names': list(resource_map.values())
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error processing JSON: {e}')
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

"

# 4. Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
head -n 20 /tmp/task_result.json
echo "..."