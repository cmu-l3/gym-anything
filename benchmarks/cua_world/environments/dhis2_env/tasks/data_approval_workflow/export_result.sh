#!/bin/bash
# Export script for Data Approval Workflow task

echo "=== Exporting Data Approval Workflow Result ==="

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
INITIAL_LEVEL_COUNT=$(cat /tmp/initial_level_count 2>/dev/null || echo "0")
INITIAL_WORKFLOW_COUNT=$(cat /tmp/initial_workflow_count 2>/dev/null || echo "0")

echo "Checking for created Data Approval Workflows..."

# 1. Fetch Workflows created after task start OR with matching name
# DHIS2 metadata often preserves 'created' timestamps, so we filter by name pattern and ID exclusion
WORKFLOW_QUERY="dataApprovalWorkflows?fields=id,name,created,periodType,dataApprovalLevels[id,name,level,orgUnitLevel]&filter=name:ilike:Health%20Data%20Review&paging=false"
WORKFLOW_JSON=$(dhis2_api "$WORKFLOW_QUERY" 2>/dev/null)

# 2. Fetch all datasets to check for assignment
DATASET_QUERY="dataSets?fields=id,name,workflow[id,name]&filter=workflow.id:!null&paging=false"
DATASET_JSON=$(dhis2_api "$DATASET_QUERY" 2>/dev/null)

# 3. Fetch all approval levels to verify existence
LEVEL_QUERY="dataApprovalLevels?fields=id,name,created,orgUnitLevel&paging=false"
LEVEL_JSON=$(dhis2_api "$LEVEL_QUERY" 2>/dev/null)

# Parse everything with Python
echo "Parsing results..."
python3 << PYEOF > /tmp/data_approval_workflow_result.json
import json
import sys
from datetime import datetime

try:
    # Load API responses
    workflow_resp = json.loads('''$WORKFLOW_JSON''')
    dataset_resp = json.loads('''$DATASET_JSON''')
    level_resp = json.loads('''$LEVEL_JSON''')
    
    task_start_iso = "$TASK_START_ISO"
    
    # Analyze Workflows
    workflows = workflow_resp.get('dataApprovalWorkflows', [])
    target_workflow = None
    
    # Find the best candidate workflow
    for w in workflows:
        if 'health data review' in w.get('name', '').lower():
            target_workflow = w
            break
            
    workflow_found = target_workflow is not None
    workflow_levels_count = 0
    workflow_created_after = False
    workflow_id = ""
    
    if workflow_found:
        workflow_id = target_workflow.get('id', '')
        levels = target_workflow.get('dataApprovalLevels', [])
        workflow_levels_count = len(levels)
        
        # Check creation time (robust parsing)
        created_str = target_workflow.get('created', '')
        try:
            # Simple string comparison often works for ISO dates
            if created_str >= task_start_iso:
                workflow_created_after = True
        except:
            pass

    # Analyze Levels
    all_levels = level_resp.get('dataApprovalLevels', [])
    # Count levels created during task (approximate via count increase or timestamps)
    current_level_count = len(all_levels)
    initial_level_count = int("$INITIAL_LEVEL_COUNT")
    net_new_levels = max(0, current_level_count - initial_level_count)

    # Analyze Dataset Assignment
    dataset_assigned = False
    assigned_dataset_name = ""
    
    if workflow_found:
        datasets = dataset_resp.get('dataSets', [])
        for ds in datasets:
            wf = ds.get('workflow', {})
            if wf.get('id') == workflow_id:
                dataset_assigned = True
                assigned_dataset_name = ds.get('name', '')
                break

    result = {
        "workflow_found": workflow_found,
        "workflow_name": target_workflow.get('name', '') if workflow_found else "",
        "workflow_levels_count": workflow_levels_count,
        "workflow_created_after": workflow_created_after,
        "net_new_levels": net_new_levels,
        "dataset_assigned": dataset_assigned,
        "assigned_dataset_name": assigned_dataset_name,
        "timestamp": datetime.now().isoformat()
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

cat /tmp/data_approval_workflow_result.json
echo "=== Export Complete ==="