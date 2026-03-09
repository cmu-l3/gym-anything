#!/bin/bash
echo "=== Exporting generate_resource_inventory result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/geoserver_inventory.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Output File Metadata
FILE_EXISTS="false"
FILE_VALID_TIME="false"
FILE_SIZE="0"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_VALID_TIME="true"
    fi
fi

# 2. Generate Ground Truth State via REST API
# We query the API *now* to see what the agent *should* have found.
echo "Gathering ground truth from GeoServer REST API..."

# Workspaces
GT_WORKSPACES=$(gs_rest_get "workspaces.json" | python3 -c "import sys,json; d=json.load(sys.stdin); ws=d.get('workspaces',{}).get('workspace',[]); print(json.dumps([w['name'] for w in (ws if isinstance(ws,list) else ([ws] if ws else []))]))" 2>/dev/null || echo "[]")
GT_WS_COUNT=$(echo "$GT_WORKSPACES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

# Styles
GT_STYLES_COUNT=$(get_style_count)

# Layer Groups
GT_GROUPS_COUNT=$(get_layergroup_count)

# Layers & DataStores (Iterate to get total counts)
# We construct a simplified ground truth structure for verification
GT_STRUCTURE=$(python3 -c "
import sys, json, requests

# Helper to fetch URL (simulating curl logic in python for complex structure)
auth = ('admin', 'Admin123!')
base_url = 'http://localhost:8080/geoserver/rest'

def get_json(endpoint):
    try:
        r = requests.get(f'{base_url}/{endpoint}', auth=auth, headers={'Accept': 'application/json'})
        if r.status_code == 200:
            return r.json()
    except:
        pass
    return {}

gt = {
    'totalWorkspaces': 0,
    'totalDataStores': 0,
    'totalLayers': 0,
    'layers': []
}

workspaces_data = get_json('workspaces.json')
ws_list = workspaces_data.get('workspaces', {}).get('workspace', [])
if isinstance(ws_list, dict): ws_list = [ws_list]

gt['totalWorkspaces'] = len(ws_list)

for ws in ws_list:
    ws_name = ws['name']
    ds_data = get_json(f'workspaces/{ws_name}/datastores.json')
    ds_list = ds_data.get('dataStores', {}).get('dataStore', [])
    if isinstance(ds_list, dict): ds_list = [ds_list]
    
    gt['totalDataStores'] += len(ds_list)
    
    for ds in ds_list:
        ds_name = ds['name']
        ft_data = get_json(f'workspaces/{ws_name}/datastores/{ds_name}/featuretypes.json')
        ft_list = ft_data.get('featureTypes', {}).get('featureType', [])
        if isinstance(ft_list, dict): ft_list = [ft_list]
        
        gt['totalLayers'] += len(ft_list)
        for ft in ft_list:
            gt['layers'].append(ft['name'])

print(json.dumps(gt))
" 2>/dev/null)

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_valid_time": $FILE_VALID_TIME,
    "file_size": $FILE_SIZE,
    "ground_truth": {
        "workspaces": $GT_WORKSPACES,
        "style_count": $GT_STYLES_COUNT,
        "group_count": $GT_GROUPS_COUNT,
        "structure": $GT_STRUCTURE
    },
    "result_nonce": "$(get_result_nonce)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="