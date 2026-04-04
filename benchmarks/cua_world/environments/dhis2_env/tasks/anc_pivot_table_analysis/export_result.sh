#!/bin/bash
# Export script for ANC Pivot Table Analysis task

echo "=== Exporting ANC Pivot Table Analysis Result ==="

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
INITIAL_DOWNLOAD_COUNT=$(cat /tmp/initial_download_count 2>/dev/null | tr -d ' ' || echo "0")

echo "Baseline: visualizations=$INITIAL_VIZ_COUNT, downloads=$INITIAL_DOWNLOAD_COUNT"

# Check for ANC-related visualizations created after task start
echo "Querying ANC-related visualizations..."
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

    anc_keywords = ['anc', 'antenatal', 'coverage', 'visit', 'maternal']
    anc_viz = [v for v in new_viz if any(k in v.get('displayName','').lower() for k in anc_keywords)]

    print(json.dumps({
        'new_count': len(new_viz),
        'anc_viz_count': len(anc_viz),
        'anc_viz_names': [v.get('displayName','') for v in anc_viz],
        'all_new_names': [v.get('displayName','') for v in new_viz[:10]],
        'has_pivot': any(v.get('type','') == 'PIVOT_TABLE' for v in new_viz)
    }))
except Exception as e:
    print(json.dumps({'new_count': 0, 'anc_viz_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_count": 0, "anc_viz_count": 0}')

NEW_VIZ_COUNT=$(echo "$VIZ_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('new_count',0))" 2>/dev/null || echo "0")
ANC_VIZ_COUNT=$(echo "$VIZ_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('anc_viz_count',0))" 2>/dev/null || echo "0")

echo "New visualizations: $NEW_VIZ_COUNT (ANC-related: $ANC_VIZ_COUNT)"

# Check Downloads for new files
echo "Checking Downloads for new files..."
DOWNLOADS_RESULT=$(python3 << 'PYEOF'
import os, json

downloads_dir = "/home/ga/Downloads"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")

new_files = []
if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, fname)
        if os.path.isfile(fpath):
            mtime = os.path.getmtime(fpath)
            if mtime >= task_start_epoch:
                ext = os.path.splitext(fname)[1].lower()
                new_files.append({"name": fname, "ext": ext})

csv_xlsx = [f for f in new_files if f["ext"] in [".csv", ".xlsx", ".xls", ".tsv"]]
print(json.dumps({
    "new_files_count": len(new_files),
    "csv_xlsx_count": len(csv_xlsx),
    "file_names": [f["name"] for f in new_files[:10]]
}))
PYEOF
)

NEW_DL_COUNT=$(echo "$DOWNLOADS_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('new_files_count',0))" 2>/dev/null || echo "0")
CSV_XLSX_COUNT=$(echo "$DOWNLOADS_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('csv_xlsx_count',0))" 2>/dev/null || echo "0")

echo "New downloads: $NEW_DL_COUNT (CSV/XLSX: $CSV_XLSX_COUNT)"

# Check analysis notes text file
echo "Checking analysis notes file..."
NOTES_EXISTS="false"
NOTES_LENGTH=0
NOTES_HAS_DISTRICT="false"
NOTES_HAS_ANC="false"

if [ -f /home/ga/Desktop/anc_analysis_notes.txt ]; then
    FILE_MTIME=$(stat -c %Y /home/ga/Desktop/anc_analysis_notes.txt 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START_EPOCH" ] 2>/dev/null; then
        NOTES_EXISTS="true"
        NOTES_LENGTH=$(wc -c < /home/ga/Desktop/anc_analysis_notes.txt 2>/dev/null || echo "0")

        # Check for district names and ANC content
        if grep -qiE "bo|kenema|kailahun|kono|bombali|tonkolili|port loko|kambia|western|pujehun|bonthe|moyamba|falaba|karene" \
               /home/ga/Desktop/anc_analysis_notes.txt 2>/dev/null; then
            NOTES_HAS_DISTRICT="true"
        fi
        if grep -qiE "anc|antenatal|coverage|visit" /home/ga/Desktop/anc_analysis_notes.txt 2>/dev/null; then
            NOTES_HAS_ANC="true"
        fi
    fi
fi

echo "Analysis notes: exists=$NOTES_EXISTS, length=$NOTES_LENGTH, has_district=$NOTES_HAS_DISTRICT, has_anc=$NOTES_HAS_ANC"

# Write result JSON
cat > /tmp/anc_pivot_table_analysis_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "new_visualization_count": $NEW_VIZ_COUNT,
    "anc_related_visualization_count": $ANC_VIZ_COUNT,
    "new_downloads_count": $NEW_DL_COUNT,
    "csv_xlsx_download_count": $CSV_XLSX_COUNT,
    "notes_file_exists": $NOTES_EXISTS,
    "notes_file_length": $NOTES_LENGTH,
    "notes_has_district_name": $NOTES_HAS_DISTRICT,
    "notes_has_anc_keywords": $NOTES_HAS_ANC,
    "visualization_detail": $VIZ_RESULT,
    "downloads_detail": $DOWNLOADS_RESULT,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/anc_pivot_table_analysis_result.json 2>/dev/null || true
echo ""
echo "Result JSON saved to /tmp/anc_pivot_table_analysis_result.json"
cat /tmp/anc_pivot_table_analysis_result.json
echo ""
echo "=== Export Complete ==="
