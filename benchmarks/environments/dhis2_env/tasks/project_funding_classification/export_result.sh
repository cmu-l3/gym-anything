#!/bin/bash
# Export script for Project Funding Classification task

echo "=== Exporting Project Funding Results ==="

source /workspace/scripts/task_utils.sh

# Fallback API function
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We will use Python to query the API and construct a comprehensive result JSON
# This avoids messy bash JSON parsing
python3 -c "
import json
import sys
import subprocess
import datetime

def api_get(endpoint):
    cmd = ['curl', '-s', '-u', 'admin:district', f'http://localhost:8080/api/{endpoint}']
    try:
        result = subprocess.check_output(cmd).decode('utf-8')
        return json.loads(result)
    except Exception as e:
        print(f'Error querying {endpoint}: {e}', file=sys.stderr)
        return {}

def parse_date(date_str):
    if not date_str: return None
    # Handle DHIS2 ISO format variations
    try:
        return datetime.datetime.fromisoformat(date_str.replace('Z', '+00:00'))
    except:
        return None

# Load task start time
try:
    with open('/tmp/task_start_iso', 'r') as f:
        task_start_iso = f.read().strip()
        task_start = datetime.datetime.fromisoformat(task_start_iso)
except:
    task_start = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)

results = {
    'options': [],
    'groups': [],
    'group_sets': [],
    'visualizations': [],
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
}

# 1. Check Category Options
# Filter for our specific project names
opt_filter = 'name:in:[Project Alpha,Project Beta,Project Gamma,Project Delta]'
opts = api_get(f'categoryOptions?filter={opt_filter}&fields=id,name,created')
if 'categoryOptions' in opts:
    results['options'] = opts['categoryOptions']

# 2. Check Category Option Groups
# Look for groups with 'Donor' or 'Fund' or 'USAID' in name
grp_filter = 'name:ilike:Donor' # Broad filter, refine in python
grps = api_get('categoryOptionGroups?fields=id,name,created,categoryOptions[id,name]&paging=false')
if 'categoryOptionGroups' in grps:
    # Filter relevant groups in python to be safe
    relevant_grps = []
    for g in grps['categoryOptionGroups']:
        n = g.get('name', '').lower()
        if 'global fund' in n or 'usaid' in n or 'donor' in n:
            relevant_grps.append(g)
    results['groups'] = relevant_grps

# 3. Check Category Option Group Sets
gs_filter = 'name:ilike:Donor'
gss = api_get('categoryOptionGroupSets?fields=id,name,created,dataDimension,categoryOptionGroups[id,name]&paging=false')
if 'categoryOptionGroupSets' in gss:
    relevant_gss = []
    for gs in gss['categoryOptionGroupSets']:
        if 'donor' in gs.get('name', '').lower() or 'funding' in gs.get('name', '').lower():
            relevant_gss.append(gs)
    results['group_sets'] = relevant_gss

# 4. Check Visualizations
viz_filter = 'name:ilike:Donor'
vizs = api_get('visualizations?fields=id,name,created,columns[id],rows[id],filters[id]&paging=false')
if 'visualizations' in vizs:
    relevant_viz = []
    for v in vizs['visualizations']:
        if 'donor' in v.get('name', '').lower() or 'funding' in v.get('name', '').lower():
            relevant_viz.append(v)
    results['visualizations'] = relevant_viz

# Output result
with open('/tmp/project_funding_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print('Export complete.')
"

echo "JSON result saved to /tmp/project_funding_result.json"
cat /tmp/project_funding_result.json
echo "=== Export Complete ==="