#!/bin/bash
# Export script for BMI Program Rule Configuration task

echo "=== Exporting BMI Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Inline API helper if needed
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# Take final screenshot (system level)
take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

# 1. Find the Program ID for Antenatal Care
echo "Locating Antenatal Care program..."
PROGRAM_INFO=$(dhis2_api "programs?filter=name:ilike:Antenatal+Care&fields=id,name,programStages[id,name]&paging=false" 2>/dev/null)
PROGRAM_ID=$(echo "$PROGRAM_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['programs'][0]['id']) if d.get('programs') else print('')" 2>/dev/null)

if [ -z "$PROGRAM_ID" ]; then
    echo "Critical Error: Antenatal Care program not found."
    # Dump empty result
    echo '{"error": "Program not found"}' > /tmp/bmi_config_result.json
    exit 0
fi
echo "Found Program ID: $PROGRAM_ID"

# 2. Find the new Data Element "BMI (Calculated)"
echo "Searching for created Data Element..."
DE_INFO=$(dhis2_api "dataElements?filter=name:ilike:BMI&fields=id,name,valueType,domainType,created&paging=false" 2>/dev/null)
# Extract the one created most recently or matching exact name
DE_JSON=$(echo "$DE_INFO" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    # Find elements created after task start (approx) or just take the best match
    # Since we can't easily parse ISO dates in bash python one-liners without libs, we return the list
    print(json.dumps(d.get('dataElements', [])))
except:
    print('[]')
")

# 3. Check Program Stage assignment
# We need to check if our BMI DE is assigned to the 'Antenatal care visit' stage
# First get the stage ID
STAGE_ID=$(echo "$PROGRAM_INFO" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    stages = d['programs'][0]['programStages']
    # Find stage with 'visit' in name
    tgt = next((s for s in stages if 'visit' in s['name'].lower()), stages[0])
    print(tgt['id'])
except:
    print('')
")

echo "Checking Program Stage $STAGE_ID..."
STAGE_ELEMENTS=""
if [ -n "$STAGE_ID" ]; then
    STAGE_DETAILS=$(dhis2_api "programStages/$STAGE_ID?fields=programStageDataElements[dataElement[id,name]]" 2>/dev/null)
    STAGE_ELEMENTS=$(echo "$STAGE_DETAILS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([x['dataElement']['id'] for x in d.get('programStageDataElements',[])]))")
fi

# 4. Check Program Rule Variables
echo "Checking Program Rule Variables..."
PRV_INFO=$(dhis2_api "programRuleVariables?filter=program.id:eq:$PROGRAM_ID&fields=id,name,dataElement[id,name],sourceType,created&paging=false" 2>/dev/null)

# 5. Check Program Rules
echo "Checking Program Rules..."
PR_INFO=$(dhis2_api "programRules?filter=program.id:eq:$PROGRAM_ID&fields=id,name,condition,programRuleActions[id,programRuleActionType,dataElement,content,data],created&paging=false" 2>/dev/null)

# 6. Check for agent screenshot
SCREENSHOT_EXISTS="false"
if [ -f "/home/ga/Desktop/bmi_verification.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Assemble all data into one JSON
python3 -c "
import json
import os

try:
    task_start = '$TASK_START_ISO'
    
    # Load gathered chunks
    de_list = $DE_JSON
    stage_de_ids = $STAGE_ELEMENTS if '$STAGE_ELEMENTS' else []
    
    prv_raw = '''$PRV_INFO'''
    prv_list = json.loads(prv_raw).get('programRuleVariables', []) if prv_raw else []
    
    pr_raw = '''$PR_INFO'''
    pr_list = json.loads(pr_raw).get('programRules', []) if pr_raw else []
    
    result = {
        'task_start_iso': task_start,
        'program_id': '$PROGRAM_ID',
        'stage_id': '$STAGE_ID',
        'data_elements_found': de_list,
        'stage_data_elements': stage_de_ids,
        'program_rule_variables': prv_list,
        'program_rules': pr_list,
        'screenshot_exists': $SCREENSHOT_EXISTS
    }
    
    with open('/tmp/bmi_config_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error building JSON: {e}')
    with open('/tmp/bmi_config_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Copy to location accessible by copy_from_env
chmod 666 /tmp/bmi_config_result.json
echo "Export complete. Result saved to /tmp/bmi_config_result.json"
cat /tmp/bmi_config_result.json