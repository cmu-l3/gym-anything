#!/bin/bash
echo "=== Exporting implement_tag_based_organization results ==="

source /workspace/scripts/task_utils.sh

# Refresh token just in case
refresh_nx_token > /dev/null 2>&1 || true

# ==============================================================================
# 1. Capture Final State
# ==============================================================================

# Get all devices to check tags
# Tags are usually in 'userAttributes.deviceTags' (comma separated string)
DEVICES_JSON=$(nx_api_get "/rest/v1/devices?_with=userAttributes")

# Get all layouts to check for 'Storm Watch'
LAYOUTS_JSON=$(nx_api_get "/rest/v1/layouts?_with=items")

# Process data into a clean JSON for verification
python3 -c "
import sys, json

try:
    devices_raw = json.loads('''$DEVICES_JSON''')
    layouts_raw = json.loads('''$LAYOUTS_JSON''')
except:
    devices_raw = []
    layouts_raw = []

result = {
    'cameras': {},
    'target_layout': None
}

# Process Cameras
for d in devices_raw:
    name = d.get('name', '')
    # userAttributes might be null if never touched, or dict
    attrs = d.get('userAttributes', {})
    if attrs is None: attrs = {}
    
    tags_str = attrs.get('deviceTags', '')
    # Normalize tags: split by comma, strip whitespace, remove empty
    tags = [t.strip() for t in tags_str.split(',') if t.strip()]
    
    result['cameras'][name] = {
        'id': d.get('id'),
        'tags': tags
    }

# Process Layout
for l in layouts_raw:
    if l.get('name', '').lower() == 'storm watch':
        layout_items = []
        for item in l.get('items', []):
            # item.resourceId is the camera ID
            res_id = item.get('resourceId')
            # Resolve ID to name for easier verification
            cam_name = next((c['name'] for c in devices_raw if c['id'] == res_id), res_id)
            layout_items.append(cam_name)
            
        result['target_layout'] = {
            'id': l.get('id'),
            'name': l.get('name'),
            'items': layout_items
        }
        break

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="