#!/bin/bash
echo "=== Exporting Inventory Thresholds Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the current state of the target drugs
# We output in a simple pipe-delimited format to parse into JSON
# Format: Name|ReorderPoint
DB_RESULTS=$(librehealth_query "SELECT name, reorder_point FROM drugs WHERE name IN ('Ibuprofen 200mg', 'Metformin 500mg')")

# Check if browser is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Construct JSON result
# Note: We manually construct JSON to avoid dependencies like jq inside the minimal environment if not present,
# though env_spec says jq is installed. Using python for reliable JSON generation.

python3 -c "
import json
import sys
import time

try:
    # Parse DB results passed via stdin
    raw_data = sys.stdin.read().strip()
    drugs_found = []
    
    if raw_data:
        # LibreHealth/MySQL default output is tab separated usually if -N is used in the util wrapper
        # The wrapper in env setup uses -N (skip column names)
        for line in raw_data.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 2:
                drugs_found.append({
                    'name': parts[0].strip(),
                    'reorder_point': int(parts[1].strip()) if parts[1].strip().isdigit() else 0
                })

    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'app_was_running': $APP_RUNNING,
        'drugs_found': drugs_found,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error creating JSON: {e}', file=sys.stderr)
    # Fallback minimal JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

" <<< "$DB_RESULTS"

# Set permissions so host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="