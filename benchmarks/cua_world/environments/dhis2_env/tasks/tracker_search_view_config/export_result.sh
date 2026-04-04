#!/bin/bash
# Export script for Tracker Search View Config task

echo "=== Exporting Tracker Search View Config Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying Child Programme configuration..."

# We need to find the program and check its attributes
# Fetching programs with 'Child' in the name
# We request fields: lastUpdated, name, and the list of attributes with their displayInList status and names
CONFIG_RESULT=$(dhis2_api "programs?filter=name:ilike:child&fields=id,displayName,lastUpdated,programTrackedEntityAttributes[id,displayInList,trackedEntityAttribute[id,name]]&paging=false" 2>/dev/null)

# Save raw result for debugging
echo "$CONFIG_RESULT" > /tmp/raw_config_result.json

# Process with Python to extract relevant status
PYTHON_SCRIPT=$(cat << 'EOF'
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    programs = data.get('programs', [])
    
    # Keyword lists (case insensitive matching)
    gender_keywords = ['gender', 'sex']
    address_keywords = ['address', 'village', 'city', 'location', 'community']
    
    results = []
    
    for prog in programs:
        prog_name = prog.get('displayName', '')
        last_updated = prog.get('lastUpdated', '')
        
        attributes = prog.get('programTrackedEntityAttributes', [])
        
        gender_visible = False
        address_visible = False
        gender_attr_name = ""
        address_attr_name = ""
        
        for attr in attributes:
            tea = attr.get('trackedEntityAttribute', {})
            tea_name = tea.get('name', '').lower()
            is_visible = attr.get('displayInList', False)
            
            # Check for Gender
            if any(k in tea_name for k in gender_keywords):
                if is_visible:
                    gender_visible = True
                    gender_attr_name = tea.get('name', '')
            
            # Check for Address
            if any(k in tea_name for k in address_keywords):
                if is_visible:
                    address_visible = True
                    address_attr_name = tea.get('name', '')
        
        results.append({
            'program_name': prog_name,
            'last_updated': last_updated,
            'gender_visible': gender_visible,
            'gender_attr_name': gender_attr_name,
            'address_visible': address_visible,
            'address_attr_name': address_attr_name
        })
    
    # Prioritize "Child Programme" if multiple found
    target_program = None
    for res in results:
        if 'child' in res['program_name'].lower():
            target_program = res
            break
    
    if not target_program and results:
        target_program = results[0]
        
    print(json.dumps({
        'found_program': bool(target_program),
        'program_details': target_program,
        'all_programs_found': results
    }))

except Exception as e:
    print(json.dumps({'found_program': False, 'error': str(e)}))
EOF
)

echo "$CONFIG_RESULT" | python3 -c "$PYTHON_SCRIPT" > /tmp/tracker_search_view_result.json 2>/dev/null

chmod 666 /tmp/tracker_search_view_result.json 2>/dev/null || true

echo "Result summary:"
cat /tmp/tracker_search_view_result.json
echo ""
echo "=== Export Complete ==="