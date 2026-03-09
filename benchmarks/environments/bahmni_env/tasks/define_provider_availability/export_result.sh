#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_block_count.txt 2>/dev/null || echo "0")
TARGET_DATE="2026-03-12"

# 3. Query OpenMRS API for blocks on the target date
echo "Querying appointment blocks for $TARGET_DATE..."
BLOCKS_RESPONSE=$(openmrs_api_get "/appointment/block?fromDate=${TARGET_DATE}T00:00:00.000&toDate=${TARGET_DATE}T23:59:59.999&v=full")

# 4. Process response with Python to extract detailed verification data
# We look for ANY block that matches our criteria
# Python script outputs a JSON object with details
EXPORT_JSON=$(python3 -c "
import sys, json, datetime

try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    current_count = len(results)
    
    found_valid_block = False
    block_details = {}
    
    target_start = '09:00:00'
    target_end = '13:00:00'
    
    for block in results:
        # Extract fields
        provider_name = block.get('provider', {}).get('person', {}).get('display', '')
        location_name = block.get('location', {}).get('display', '')
        start_dt = block.get('startDate', '')  # ISO format usually
        end_dt = block.get('endDate', '')
        audit = block.get('auditInfo', {})
        date_created = audit.get('dateCreated', '')
        
        # Simple time extraction (assuming ISO format like 2026-03-12T09:00:00.000+0000)
        # We just grab the time part string for simplicity or robust parsing
        actual_start_time = start_dt.split('T')[1].split('.')[0] if 'T' in start_dt else ''
        actual_end_time = end_dt.split('T')[1].split('.')[0] if 'T' in end_dt else ''
        
        # Check against targets (loose check here, strict in verifier)
        # We export the BEST match we can find
        if 'Superman' in provider_name:
            found_valid_block = True
            block_details = {
                'uuid': block.get('uuid'),
                'provider': provider_name,
                'location': location_name,
                'startDate': start_dt,
                'endDate': end_dt,
                'startTime': actual_start_time,
                'endTime': actual_end_time,
                'dateCreated': date_created
            }
            # If this matches times exactly, break, otherwise keep looking for better match
            if actual_start_time == target_start and actual_end_time == target_end:
                break
                
    print(json.dumps({
        'current_count': current_count,
        'found_block': found_valid_block,
        'block_details': block_details,
        'raw_results_count': len(results)
    }))

except Exception as e:
    print(json.dumps({'error': str(e), 'current_count': 0}))
" <<< "$BLOCKS_RESPONSE")

# 5. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "api_data": $EXPORT_JSON,
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
echo "=== Export complete ==="