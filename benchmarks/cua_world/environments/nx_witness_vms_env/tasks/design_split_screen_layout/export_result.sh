#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Export Layout Data from API
echo "Fetching layout configuration..."
# We need the list of all layouts to find "Gate Monitor"
ALL_LAYOUTS=$(get_all_layouts)
echo "$ALL_LAYOUTS" > /tmp/all_layouts.json

# 3. Export specific layout details if found
LAYOUT_DATA=$(echo "$ALL_LAYOUTS" | python3 -c "
import sys, json
try:
    layouts = json.load(sys.stdin)
    target = next((l for l in layouts if l.get('name') == 'Gate Monitor'), None)
    print(json.dumps(target) if target else '{}')
except:
    print('{}')
")
echo "$LAYOUT_DATA" > /tmp/target_layout.json

# 4. Capture Final Screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
# We bundle everything into a JSON for the python verifier to parse easily
python3 -c "
import json
import os
import time

try:
    with open('/tmp/target_layout.json', 'r') as f:
        layout = json.load(f)
        
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'layout_found': bool(layout and layout.get('id')),
        'layout_data': layout,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error creating result JSON: {e}')
    # Fallback
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# 6. Set permissions so the verifier (running as root/user) can read it
chmod 644 /tmp/task_result.json
chmod 644 /tmp/all_layouts.json 2>/dev/null || true
chmod 644 /tmp/target_layout.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"