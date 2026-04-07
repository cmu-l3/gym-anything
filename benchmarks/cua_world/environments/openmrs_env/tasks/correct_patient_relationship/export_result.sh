#!/bin/bash
echo "=== Exporting Relationship Task Results ==="
source /workspace/scripts/task_utils.sh

# Recover UUIDs
CHILD_PERSON_UUID=$(cat /tmp/child_person_uuid.txt)
PARENT_PERSON_UUID=$(cat /tmp/parent_person_uuid.txt)
TASK_START_TIME=$(cat /tmp/task_start_time.txt)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Current Relationships for Child
echo "Fetching final relationships..."
RELATIONSHIPS_JSON=$(omrs_get "/relationship?person=$CHILD_PERSON_UUID&v=full")

# Save to temp file for Python processing
echo "$RELATIONSHIPS_JSON" > /tmp/relationships_dump.json

# Process with Python to extract the relevant relationship status
python3 -c "
import json
import sys
import time

child_uuid = '$CHILD_PERSON_UUID'
parent_uuid = '$PARENT_PERSON_UUID'
task_start = float('$TASK_START_TIME')

try:
    with open('/tmp/relationships_dump.json') as f:
        data = json.load(f)
except:
    data = {'results': []}

# Define Expected UUIDs
REL_TYPE_PARENT = '8d91a210-c2cc-11de-8d13-0010c6dffd0f' # A is Parent of B
REL_TYPE_SIBLING = '8d91a01c-c2cc-11de-8d13-0010c6dffd0f'

found_parent_rel = False
found_sibling_rel = False
is_correct_direction = False
rel_uuid = ''
last_updated = 0

for r in data.get('results', []):
    if r.get('voided'): continue
    
    # Check participants
    pa = r.get('personA', {}).get('uuid')
    pb = r.get('personB', {}).get('uuid')
    
    # We are looking for the link between Child and Parent
    if (pa == child_uuid and pb == parent_uuid) or (pa == parent_uuid and pb == child_uuid):
        rtype = r.get('relationshipType', {}).get('uuid')
        
        # Check timestamps (rough ISO parse)
        # Note: OpenMRS REST API dates are ISO8601. 
        # For simplicity in bash context, we might trust presence if Type is correct.
        
        if rtype == REL_TYPE_SIBLING:
            found_sibling_rel = True
            
        if rtype == REL_TYPE_PARENT:
            found_parent_rel = True
            rel_uuid = r.get('uuid')
            # For Parent Type: Person A is Parent, Person B is Child
            # We want Martha (Parent) -> Bobby (Child)
            # So Person A should be PARENT_UUID
            if pa == parent_uuid and pb == child_uuid:
                is_correct_direction = True
            else:
                is_correct_direction = False

result = {
    'found_parent_rel': found_parent_rel,
    'found_sibling_rel': found_sibling_rel,
    'is_correct_direction': is_correct_direction,
    'rel_uuid': rel_uuid,
    'task_start_ts': task_start,
    'timestamp': time.time(),
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json