#!/bin/bash
echo "=== Exporting Create Care Setting Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenMRS API for the Care Setting
echo "Querying OpenMRS API for 'Telemedicine'..."
API_RESPONSE=$(openmrs_api_get "/caresetting?v=full")

# Extract details using Python for robustness
RESULT_JSON=$(echo "$API_RESPONSE" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    
    target = None
    for r in results:
        # Check name (case-insensitive mostly, but API is usually strict)
        if r.get('name', '') == 'Telemedicine':
            target = r
            break
            
    if target:
        output = {
            'found': True,
            'name': target.get('name'),
            'description': target.get('description', ''),
            'careSettingType': target.get('careSettingType'),
            'retired': target.get('retired', False),
            'uuid': target.get('uuid')
        }
    else:
        output = {
            'found': False
        }
    
    # Add count info
    output['total_count'] = len(results)
    
    print(json.dumps(output))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Construct final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "api_result": $RESULT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="