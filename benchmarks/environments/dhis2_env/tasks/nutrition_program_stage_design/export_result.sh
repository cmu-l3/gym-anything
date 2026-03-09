#!/bin/bash
# Export script for Nutrition Program Stage Design task

echo "=== Exporting Nutrition Program Stage Design Result ==="

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

echo "Analyzing Child Programme configuration..."

# We need to find the Child Programme ID first, then inspect its stages
# We pull a deep nested structure to verify everything in one go
RESULT_JSON=$(python3 -c "
import requests, json, sys
from datetime import datetime

auth = ('admin', 'district')
base_url = 'http://localhost:8080/api'
task_start_iso = '$TASK_START_ISO'

def parse_date(s):
    if not s: return datetime.min
    try:
        # Handle 2023-10-25T10:00:00.000 (no Z or offset)
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except:
        return datetime.min

def get_child_program():
    # Try to find the child program
    keywords = ['Child Programme', 'Child Health', 'MNCH', 'Under 5']
    
    # Get all programs to search client-side for better matching
    r = requests.get(f'{base_url}/programs?fields=id,displayName,programStages[id,displayName,repeatable,created,programStageDataElements[dataElement[id,displayName]],programStageSections[id,displayName,dataElements[id,displayName]]]&paging=false', auth=auth)
    
    if r.status_code != 200:
        return {'error': f'API Error {r.status_code}'}
        
    programs = r.json().get('programs', [])
    target_prog = None
    
    # Simple keyword match
    for p in programs:
        name = p.get('displayName', '')
        if any(k in name for k in keywords):
            target_prog = p
            # Prefer 'Child Programme' exact match if multiple
            if 'Child Programme' in name:
                break
    
    if not target_prog:
        return {'program_found': False}

    prog_result = {
        'program_found': True,
        'program_name': target_prog.get('displayName'),
        'program_id': target_prog.get('id'),
        'target_stage_found': False,
        'stage_details': {}
    }

    # Look for the specific stage
    stages = target_prog.get('programStages', [])
    nutrition_stage = None
    
    for s in stages:
        if 'Nutrition Screening' in s.get('displayName', ''):
            nutrition_stage = s
            break
            
    if nutrition_stage:
        # Check sections
        sections = nutrition_stage.get('programStageSections', [])
        anthropometry_section = None
        for sec in sections:
            if 'Anthropometry' in sec.get('displayName', ''):
                anthropometry_section = sec
                break
        
        # Get data elements in the stage
        stage_des = []
        raw_des = nutrition_stage.get('programStageDataElements', [])
        for item in raw_des:
            de = item.get('dataElement', {})
            stage_des.append(de.get('displayName', ''))
            
        # Get data elements in the section (if it exists)
        section_des = []
        if anthropometry_section:
            for de in anthropometry_section.get('dataElements', []):
                section_des.append(de.get('displayName', ''))

        prog_result['target_stage_found'] = True
        prog_result['stage_details'] = {
            'name': nutrition_stage.get('displayName'),
            'id': nutrition_stage.get('id'),
            'repeatable': nutrition_stage.get('repeatable'),
            'created': nutrition_stage.get('created'),
            'data_elements': stage_des,
            'section_found': bool(anthropometry_section),
            'section_name': anthropometry_section.get('displayName') if anthropometry_section else None,
            'section_data_elements': section_des
        }

    return prog_result

print(json.dumps(get_child_program()))
")

echo "$RESULT_JSON" > /tmp/nutrition_stage_result.json
chmod 666 /tmp/nutrition_stage_result.json

echo "Result JSON saved:"
cat /tmp/nutrition_stage_result.json
echo ""
echo "=== Export Complete ==="