#!/bin/bash
# Export script for Immunization Dropout Scatter Plot task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Capture Final State
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Timestamps
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+00:00")
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_VIZ_COUNT=$(cat /tmp/initial_viz_count 2>/dev/null || echo "0")

# 3. Check Downloads (File System Verification)
echo "Checking Downloads folder..."
DOWNLOAD_JSON=$(python3 << EOF
import os, json, time

downloads_dir = "/home/ga/Downloads"
start_time = $TASK_START_EPOCH
files = []

if os.path.exists(downloads_dir):
    for f in os.listdir(downloads_dir):
        path = os.path.join(downloads_dir, f)
        if os.path.isfile(path):
            mtime = os.path.getmtime(path)
            if mtime >= start_time:
                files.append({
                    "name": f,
                    "size": os.path.getsize(path),
                    "ext": os.path.splitext(f)[1].lower()
                })

print(json.dumps(files))
EOF
)

# 4. Query DHIS2 API (Metadata Verification)
echo "Querying DHIS2 Visualizations..."
# Fetch detailed fields to verify configuration: type, publicAccess, data dimensions, org units
API_RESPONSE=$(dhis2_api "visualizations?fields=id,displayName,created,type,publicAccess,columns[dimension,items[id,displayName]],rows[dimension,items[id,displayName]],filters[dimension,items[id,displayName]]&order=created:desc&pageSize=5" 2>/dev/null)

# 5. Process API Data with Python
# We need to find if a SCATTER plot was created after task start
VIZ_ANALYSIS=$(python3 << EOF
import json, sys
from datetime import datetime

try:
    task_start_iso = "$TASK_START_ISO".replace('Z', '+00:00')
    # Handle basic ISO format issues
    if task_start_iso.endswith('+0000'):
        task_start_iso = task_start_iso[:-5] + '+00:00'
    
    task_start = datetime.fromisoformat(task_start_iso)
    
    api_data = json.loads('''$API_RESPONSE''')
    visualizations = api_data.get('visualizations', [])
    
    target_viz = None
    created_count = 0
    
    for viz in visualizations:
        created_str = viz.get('created', '')
        # DHIS2 sometimes returns '2023-10-25T12:00:00.123' without TZ, assume UTC/Server time
        if not created_str: continue
        
        # Normalize date string for comparison
        if created_str.endswith('Z'): created_str = created_str[:-1] + '+00:00'
        try:
            created_dt = datetime.fromisoformat(created_str)
            # Rough comparison if TZ info is missing in one
            if created_dt.replace(tzinfo=None) >= task_start.replace(tzinfo=None):
                created_count += 1
                # Check if this is likely our target
                name = viz.get('displayName', '').lower()
                vtype = viz.get('type', '')
                
                # Priority: SCATTER type + relevant name
                if vtype == 'SCATTER' and ('penta' in name or 'scatter' in name):
                    target_viz = viz
                    break
                # Fallback: Just SCATTER type created recently
                elif vtype == 'SCATTER' and not target_viz:
                    target_viz = viz
        except Exception as e:
            continue

    result = {
        "new_viz_count": created_count,
        "found": bool(target_viz),
        "viz_data": target_viz if target_viz else {}
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "found": False}))
EOF
)

# 6. Compile Final Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_iso": "$TASK_START_ISO",
    "downloads": $DOWNLOAD_JSON,
    "api_analysis": $VIZ_ANALYSIS,
    "initial_viz_count": $INITIAL_VIZ_COUNT
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result summary:"
cat /tmp/task_result.json