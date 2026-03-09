#!/bin/bash
echo "=== Exporting upload_patient_document results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso.txt 2>/dev/null || echo "")
TARGET_PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null || echo "")

echo "Task duration: $((TASK_END - TASK_START)) seconds"
echo "Target Patient UUID: $TARGET_PATIENT_UUID"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
OBS_FOUND="false"
OBS_UUID=""
OBS_DISPLAY=""
OBS_DATETIME=""
OBS_VALUE=""
IS_COMPLEX="false"
FILENAME_MATCH="false"

if [ -n "$TARGET_PATIENT_UUID" ]; then
    # Query OpenMRS for observations for this patient
    # We fetch full representation to see complex values (file links)
    echo "Querying observations for patient..."
    
    # Note: OpenMRS API might default to 50 results. Sorting by date desc helps find new ones.
    # We can't easily sort via REST API parameters in all versions, so we fetch recent ones.
    API_RESPONSE=$(openmrs_api_get "/obs?patient=${TARGET_PATIENT_UUID}&v=full&limit=20")
    
    # Save raw response for debugging
    echo "$API_RESPONSE" > /tmp/obs_debug.json
    
    # Parse with python to handle date comparison and complex object logic robustly
    python3 -c "
import json
import sys
import datetime

try:
    data = json.load(open('/tmp/obs_debug.json'))
    start_time_iso = '$TASK_START_ISO'
    # Simple string comparison for ISO dates often works if formats align, 
    # but let's try to find *any* obs created after start.
    
    results = data.get('results', [])
    found_obs = None
    
    for obs in results:
        # Check date. OpenMRS format: 2024-12-15T10:00:00.000+0000
        obs_date = obs.get('obsDatetime', '')
        
        # Determine if this is a file upload
        # 1. Datatype might be Complex
        # 2. Value might be a complex object with specific keys
        # 3. Display might indicate the file
        
        is_complex = False
        concept = obs.get('concept', {})
        datatype = concept.get('datatype', {}).get('display', '')
        
        if 'Complex' in datatype or 'Document' in datatype:
            is_complex = True
            
        value = obs.get('value', '')
        value_str = str(value)
        
        # Check if it was created during task
        # We'll be lenient and just check if it's the most recent or matches the filename
        # provided we know the task started recently.
        # A robust check compares timestamps.
        
        if 'external_lab_report' in value_str or 'external_lab_report' in obs.get('display', ''):
             found_obs = obs
             break
             
    if found_obs:
        print(json.dumps({
            'found': True,
            'uuid': found_obs.get('uuid'),
            'display': found_obs.get('display'),
            'value': str(found_obs.get('value')),
            'obsDatetime': found_obs.get('obsDatetime'),
            'concept': found_obs.get('concept', {}).get('display')
        }))
    else:
        print(json.dumps({'found': False}))

except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" > /tmp/parsed_obs.json

    # Load parsed results
    if [ -f /tmp/parsed_obs.json ]; then
        OBS_FOUND=$(jq -r '.found' /tmp/parsed_obs.json)
        if [ "$OBS_FOUND" = "true" ]; then
            OBS_UUID=$(jq -r '.uuid' /tmp/parsed_obs.json)
            OBS_VALUE=$(jq -r '.value' /tmp/parsed_obs.json)
            OBS_DISPLAY=$(jq -r '.display' /tmp/parsed_obs.json)
            
            if [[ "$OBS_VALUE" == *"external_lab_report"* ]] || [[ "$OBS_DISPLAY" == *"external_lab_report"* ]]; then
                FILENAME_MATCH="true"
            fi
        fi
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_patient_uuid": "$TARGET_PATIENT_UUID",
    "observation_found": $OBS_FOUND,
    "observation_uuid": "$OBS_UUID",
    "observation_value": "$OBS_VALUE",
    "observation_display": "$OBS_DISPLAY",
    "filename_match": $FILENAME_MATCH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="