#!/bin/bash
set -u

echo "=== Exporting Create Program Definition Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PROG_COUNT=$(cat /tmp/initial_program_count.txt 2>/dev/null || echo "0")

# 1. Query Program "Nutrition Support"
echo "Querying Program..."
PROGRAM_RESP=$(openmrs_api_get "/program?q=Nutrition+Support&v=full")
# Save raw response for debug
echo "$PROGRAM_RESP" > /tmp/debug_program_resp.json

# 2. Query Concept "Nutrition Support Program"
echo "Querying Concept..."
CONCEPT_RESP=$(openmrs_api_get "/concept?q=Nutrition+Support+Program&v=full")
# Save raw response for debug
echo "$CONCEPT_RESP" > /tmp/debug_concept_resp.json

# 3. Get total program count
ALL_PROGS=$(openmrs_api_get "/program?v=default")
FINAL_PROG_COUNT=$(echo "$ALL_PROGS" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Construct Result JSON
# We use python to robustly parse the API responses and construct the result
python3 -c "
import json
import sys
import os

try:
    # Load API responses
    with open('/tmp/debug_program_resp.json', 'r') as f:
        prog_data = json.load(f)
    with open('/tmp/debug_concept_resp.json', 'r') as f:
        concept_data = json.load(f)
    
    # Analyze Program
    programs = prog_data.get('results', [])
    target_program = None
    for p in programs:
        if p.get('name') == 'Nutrition Support':
            target_program = p
            break
            
    # Analyze Concept
    concepts = concept_data.get('results', [])
    target_concept = None
    for c in concepts:
        # Check names (fully specified or display)
        name_match = False
        if c.get('display') == 'Nutrition Support Program':
            name_match = True
        elif c.get('name', {}).get('display') == 'Nutrition Support Program':
            name_match = True
            
        if name_match:
            target_concept = c
            break

    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'initial_prog_count': int('$INITIAL_PROG_COUNT'),
        'final_prog_count': int('$FINAL_PROG_COUNT'),
        'program_found': target_program is not None,
        'concept_found': target_concept is not None,
        'program_details': {},
        'concept_details': {},
        'screenshot_path': '/tmp/task_final.png'
    }

    if target_program:
        # Extract linkage
        concept_link = target_program.get('concept', {})
        result['program_details'] = {
            'uuid': target_program.get('uuid'),
            'name': target_program.get('name'),
            'description': target_program.get('description'),
            'date_created': target_program.get('auditInfo', {}).get('dateCreated'),
            'concept_link_name': concept_link.get('display')
        }

    if target_concept:
        result['concept_details'] = {
            'uuid': target_concept.get('uuid'),
            'name': target_concept.get('display'),
            'class': target_concept.get('conceptClass', {}).get('display'),
            'datatype': target_concept.get('datatype', {}).get('display'),
            'date_created': target_concept.get('auditInfo', {}).get('dateCreated')
        }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(f'Error processing results: {e}', file=sys.stderr)
    # Write a fallback error json
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="