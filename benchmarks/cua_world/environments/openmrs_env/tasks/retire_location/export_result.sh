#!/bin/bash
# Export: retire_location task
# Fetches the final state of the target location from the API.

echo "=== Exporting retire_location results ==="
source /workspace/scripts/task_utils.sh

# Get the UUID we stored during setup
if [ -f /tmp/target_location_uuid.txt ]; then
    LOCATION_UUID=$(cat /tmp/target_location_uuid.txt)
else
    # Fallback search if tmp file missing
    LOCATION_NAME="Temporary Fever Clinic"
    SEARCH_RESULT=$(omrs_get "/location?q=$(echo "$LOCATION_NAME" | sed 's/ /%20/g')&v=default")
    LOCATION_UUID=$(echo "$SEARCH_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('results', [{}])[0].get('uuid', ''))")
fi

if [ -z "$LOCATION_UUID" ]; then
    echo "ERROR: Could not verify location state - UUID not found."
    exit 1
fi

echo "Fetching final state for Location: $LOCATION_UUID"

# Fetch full details including audit info (for timestamps)
LOCATION_JSON=$(omrs_get "/location/$LOCATION_UUID?v=full")

# Save raw API response to a temp file
echo "$LOCATION_JSON" > /tmp/location_final_state.json

# Capture final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Capture timestamps
TASK_START_ISO=$(cat /tmp/task_start_iso.txt 2>/dev/null || echo "")
TASK_START_TS=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
NOW_TS=$(date +%s)

# Create the result JSON structure
# We extract key fields here to make verifier's job easier/safer
python3 -c "
import sys, json

try:
    with open('/tmp/location_final_state.json', 'r') as f:
        loc = json.load(f)
        
    result = {
        'uuid': loc.get('uuid'),
        'name': loc.get('name'),
        'retired': loc.get('retired', False),
        'retireReason': loc.get('retireReason', ''),
        'auditInfo': loc.get('auditInfo', {}),
        'task_start_iso': '$TASK_START_ISO',
        'task_start_ts': $TASK_START_TS,
        'export_ts': $NOW_TS,
        'screenshot_path': '/tmp/task_final_screenshot.png'
    }
    
    with open('/tmp/task_result.json', 'w') as out:
        json.dump(result, out, indent=2)
        
except Exception as e:
    print(f'Error processing JSON: {e}')
    # Fallback empty result
    with open('/tmp/task_result.json', 'w') as out:
        json.dump({'error': str(e)}, out)
"

# Set permissions so host can copy it
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final_screenshot.png 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json