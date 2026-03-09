#!/bin/bash
# Export script for TB Programme Data Export task

echo "=== Exporting TB Programme Data Export Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read baseline values
INITIAL_DOWNLOAD_COUNT=$(cat /tmp/initial_download_count 2>/dev/null | tr -d ' ' || echo "0")
INITIAL_VIZ_COUNT=$(cat /tmp/initial_visualization_count 2>/dev/null | tr -d ' ' || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' ' || echo "0")

echo "Baseline: downloads=$INITIAL_DOWNLOAD_COUNT, visualizations=$INITIAL_VIZ_COUNT"

# Check Downloads folder for new files
echo "Checking Downloads folder..."
DOWNLOADS_RESULT=$(python3 << 'PYEOF'
import os, time, json

downloads_dir = "/home/ga/Downloads"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")
initial_count = int(open("/tmp/initial_download_count").read().strip() or "0")

all_files = []
new_files = []

if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, fname)
        if os.path.isfile(fpath):
            mtime = os.path.getmtime(fpath)
            all_files.append({"name": fname, "mtime": mtime})
            if mtime >= task_start_epoch:
                ext = os.path.splitext(fname)[1].lower()
                new_files.append({"name": fname, "mtime": mtime, "ext": ext})

new_files.sort(key=lambda x: x["mtime"], reverse=True)
csv_xlsx_count = sum(1 for f in new_files if f["ext"] in [".csv", ".xlsx", ".xls", ".json", ".tsv"])

print(json.dumps({
    "total_files": len(all_files),
    "new_files_count": len(new_files),
    "csv_xlsx_new_count": csv_xlsx_count,
    "new_file_names": [f["name"] for f in new_files[:10]]
}))
PYEOF
)

NEW_DL_COUNT=$(echo "$DOWNLOADS_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('new_files_count', 0))" 2>/dev/null || echo "0")
CSV_XLSX_COUNT=$(echo "$DOWNLOADS_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('csv_xlsx_new_count', 0))" 2>/dev/null || echo "0")
echo "New downloads: $NEW_DL_COUNT (CSV/XLSX: $CSV_XLSX_COUNT)"

# Check for new visualizations
echo "Querying recent visualizations..."
VIZ_RESULT=$(dhis2_api "visualizations?fields=id,displayName,created,type&paging=false&order=created:desc&pageSize=50" 2>/dev/null | \
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

    new_viz = []
    for v in data.get('visualizations', []):
        created_str = v.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            if created >= task_start:
                new_viz.append(v)
        except:
            pass

    tb_viz = [v for v in new_viz if any(k in v.get('displayName','').lower()
              for k in ['tb', 'tuberculosis', 'notification', 'western area', 'case'])]

    print(json.dumps({
        'new_count': len(new_viz),
        'tb_viz_count': len(tb_viz),
        'tb_viz_names': [v.get('displayName','') for v in tb_viz],
        'all_new_names': [v.get('displayName','') for v in new_viz[:10]]
    }))
except Exception as e:
    print(json.dumps({'new_count': 0, 'tb_viz_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_count": 0, "tb_viz_count": 0}')

NEW_VIZ_COUNT=$(echo "$VIZ_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('new_count', 0))" 2>/dev/null || echo "0")
TB_VIZ_COUNT=$(echo "$VIZ_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tb_viz_count', 0))" 2>/dev/null || echo "0")
echo "New visualizations: $NEW_VIZ_COUNT (TB-related: $TB_VIZ_COUNT)"

# Write result JSON
cat > /tmp/tb_programme_data_export_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "initial_download_count": $INITIAL_DOWNLOAD_COUNT,
    "initial_visualization_count": $INITIAL_VIZ_COUNT,
    "new_downloads_count": $NEW_DL_COUNT,
    "csv_xlsx_new_count": $CSV_XLSX_COUNT,
    "new_visualization_count": $NEW_VIZ_COUNT,
    "tb_related_visualization_count": $TB_VIZ_COUNT,
    "downloads_detail": $DOWNLOADS_RESULT,
    "visualization_detail": $VIZ_RESULT,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/tb_programme_data_export_result.json 2>/dev/null || true
echo ""
echo "Result JSON saved to /tmp/tb_programme_data_export_result.json"
cat /tmp/tb_programme_data_export_result.json
echo ""
echo "=== Export Complete ==="
