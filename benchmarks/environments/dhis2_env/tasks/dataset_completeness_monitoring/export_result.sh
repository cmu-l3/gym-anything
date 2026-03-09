#!/bin/bash
# Export script for Dataset Completeness Monitoring task

echo "=== Exporting Dataset Completeness Monitoring Result ==="

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
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' ' || echo "0")
INITIAL_VIZ_COUNT=$(cat /tmp/initial_visualization_count 2>/dev/null | tr -d ' ' || echo "0")

# 1. Analyze Visualizations
# We need to check if a new visualization was created that uses REPORTING_RATE
echo "Querying recent visualizations..."
VIZ_RESULT=$(dhis2_api "visualizations?fields=id,displayName,created,type,dataDimensionItems&paging=false&order=created:desc&pageSize=20" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    # Simple ISO parsing fallback
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    new_viz = []
    completeness_viz = []
    uses_reporting_rate = False

    for v in data.get('visualizations', []):
        created_str = v.get('created', '2020-01-01T00:00:00')
        try:
            # Handle DHIS2 ISO format variations
            clean_date = created_str.replace('Z','+00:00').replace('+0000','+00:00')
            created = datetime.fromisoformat(clean_date)
            
            if created >= task_start:
                new_viz.append(v)
                
                # Check name
                name = v.get('displayName', '').lower()
                is_target_name = 'completeness' in name or 'reporting' in name
                
                # Check dimensions for Reporting Rate
                # DHIS2 uses 'reportingRate' object or dataDimensionItemType='REPORTING_RATE'
                has_rr = False
                dims = v.get('dataDimensionItems', [])
                for d in dims:
                    if d.get('dataDimensionItemType') == 'REPORTING_RATE' or 'reportingRate' in d:
                        has_rr = True
                        break
                
                if is_target_name:
                    completeness_viz.append({'id': v['id'], 'name': v['displayName'], 'has_rr': has_rr})
                
                if has_rr:
                    uses_reporting_rate = True
        except Exception as e:
            continue

    print(json.dumps({
        'new_viz_count': len(new_viz),
        'completeness_viz_count': len(completeness_viz),
        'completeness_viz_details': completeness_viz,
        'any_uses_reporting_rate': uses_reporting_rate
    }))
except Exception as e:
    print(json.dumps({'error': str(e), 'new_viz_count': 0}))
" 2>/dev/null)

# 2. Check Downloads
echo "Checking Downloads..."
DOWNLOADS_RESULT=$(python3 << 'PYEOF'
import os, json

downloads_dir = "/home/ga/Downloads"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")
initial_files = set(open("/tmp/initial_downloads.txt").read().splitlines()) if os.path.exists("/tmp/initial_downloads.txt") else set()

new_files = []
if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        if fname not in initial_files:
            fpath = os.path.join(downloads_dir, fname)
            if os.path.isfile(fpath):
                mtime = os.path.getmtime(fpath)
                if mtime >= task_start_epoch:
                    new_files.append(fname)

csv_xlsx = [f for f in new_files if f.lower().endswith(('.csv', '.xlsx', '.xls', '.json'))]

print(json.dumps({
    "new_download_count": len(new_files),
    "valid_export_count": len(csv_xlsx),
    "files": new_files
}))
PYEOF
)

# 3. Check Summary File
echo "Checking Summary File..."
SUMMARY_FILE="/home/ga/Desktop/completeness_summary.txt"
SUMMARY_EXISTS="false"
SUMMARY_CONTENT=""
SUMMARY_LENGTH=0
HAS_DISTRICT="false"
HAS_PERCENT="false"

if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_CONTENT=$(cat "$SUMMARY_FILE")
    SUMMARY_LENGTH=${#SUMMARY_CONTENT}
    
    # Simple grep checks for content validity
    if grep -qiE "bo|kenema|kailahun|kono|bombali|tonkolili|port loko|kambia|western|pujehun|bonthe|moyamba|falaba|karene" "$SUMMARY_FILE"; then
        HAS_DISTRICT="true"
    fi
    if grep -qE "[0-9]+%|80|percentage|rate" "$SUMMARY_FILE"; then
        HAS_PERCENT="true"
    fi
fi

# Write Result JSON
cat > /tmp/completeness_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "visualization_analysis": $VIZ_RESULT,
    "downloads_analysis": $DOWNLOADS_RESULT,
    "summary_file": {
        "exists": $SUMMARY_EXISTS,
        "length": $SUMMARY_LENGTH,
        "has_district": $HAS_DISTRICT,
        "has_percent_or_rate": $HAS_PERCENT
    },
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

echo "Result saved to /tmp/completeness_result.json"