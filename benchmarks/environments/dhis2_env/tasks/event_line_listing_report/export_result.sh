#!/bin/bash
# Export script for Event Line Listing Report task

echo "=== Exporting Event Line Listing Report Result ==="

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

# 1. Check for new Event Reports (Legacy App)
echo "Checking for new Event Reports..."
NEW_REPORTS=$(dhis2_api "eventReports?fields=id,displayName,created,type,program[id,displayName]&paging=false&order=created:desc" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        # Simple ISO parse attempt
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    new_items = []
    for item in data.get('eventReports', []):
        created_str = item.get('created', '')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000', '+00:00'))
            if created >= task_start:
                new_items.append(item)
        except:
            pass
    print(json.dumps(new_items))
except Exception as e:
    print(json.dumps([]))
" 2>/dev/null)

# 2. Check for new Event Visualizations (New Line Listing App / Data Visualizer)
echo "Checking for new Event Visualizations..."
NEW_VIZ=$(dhis2_api "eventVisualizations?fields=id,displayName,created,type,program[id,displayName]&paging=false&order=created:desc" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('+0000', '+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    new_items = []
    for item in data.get('eventVisualizations', []):
        created_str = item.get('created', '')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000', '+00:00'))
            if created >= task_start:
                new_items.append(item)
        except:
            pass
    print(json.dumps(new_items))
except Exception as e:
    print(json.dumps([]))
" 2>/dev/null)

# 3. Check Downloads
echo "Checking Downloads..."
DOWNLOADS_DATA=$(python3 << 'PYEOF'
import os, json, time

downloads_dir = "/home/ga/Downloads"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")
initial_files = []
try:
    with open("/tmp/initial_downloads_list.txt") as f:
        initial_files = [l.strip() for l in f.readlines()]
except:
    pass

new_files = []
if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, fname)
        if os.path.isfile(fpath):
            mtime = os.path.getmtime(fpath)
            # Check if file is new based on time AND not in initial list
            if mtime >= task_start_epoch and fname not in initial_files:
                size = os.path.getsize(fpath)
                ext = os.path.splitext(fname)[1].lower()
                new_files.append({
                    "name": fname,
                    "ext": ext,
                    "size": size,
                    "mtime": mtime
                })

# Filter for data files
valid_exports = [f for f in new_files if f["ext"] in [".csv", ".xls", ".xlsx", ".html", ".json"]]
print(json.dumps({
    "new_file_count": len(new_files),
    "valid_export_count": len(valid_exports),
    "files": valid_exports
}))
PYEOF
)

# Combine results
cat > /tmp/event_line_listing_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "new_event_reports": $NEW_REPORTS,
    "new_event_visualizations": $NEW_VIZ,
    "downloads": $DOWNLOADS_DATA,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/event_line_listing_result.json 2>/dev/null || true
echo "Result JSON saved."
cat /tmp/event_line_listing_result.json
echo "=== Export Complete ==="