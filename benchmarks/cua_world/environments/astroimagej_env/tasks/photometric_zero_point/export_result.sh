#!/bin/bash
echo "=== Exporting photometric_zero_point task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check CSV
CSV_PATH="/home/ga/AstroImages/measurements/m12_photometry.csv"
CSV_EXISTS="false"
CSV_CONTENT=""
CSV_MTIME="0"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_CONTENT=$(head -n 100 "$CSV_PATH" | base64 -w 0)
fi

# Check JSON
JSON_PATH="/home/ga/AstroImages/processed/zero_point_report.json"
JSON_EXISTS="false"
JSON_CONTENT=""
JSON_MTIME="0"
if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    JSON_CONTENT=$(cat "$JSON_PATH" | base64 -w 0)
fi

# Check AIJ running
APP_RUNNING=$(pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null && echo "true" || echo "false")

# Extract V mags from the catalog
python3 << 'PYEOF'
import json
try:
    import xlrd
except ImportError:
    import subprocess
    subprocess.call(["pip3", "install", "xlrd"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    import xlrd

result = {'v_mags': [], 'headers': [], 'error': None}
try:
    wb = xlrd.open_workbook('/opt/fits_samples/m12/m12_B_V.xls')
    sheet = wb.sheet_by_index(0)
    
    headers = [str(sheet.cell_value(0, i)).strip().upper() for i in range(sheet.ncols)]
    result['headers'] = headers
    
    v_col = -1
    for i, h in enumerate(headers):
        if h == 'V' or 'VMAG' in h or 'V_MAG' in h:
            v_col = i
            break
            
    if v_col != -1:
        for row in range(1, min(6, sheet.nrows)):
            try:
                val = float(sheet.cell_value(row, v_col))
                result['v_mags'].append(val)
            except:
                pass
except Exception as e:
    result['error'] = str(e)

with open('/tmp/m12_v_mags.json', 'w') as f:
    json.dump(result, f)
PYEOF

V_MAGS_JSON=$(cat /tmp/m12_v_mags.json 2>/dev/null || echo '{"v_mags":[]}')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_mtime": $CSV_MTIME,
    "csv_content_b64": "$CSV_CONTENT",
    "json_exists": $JSON_EXISTS,
    "json_mtime": $JSON_MTIME,
    "json_content_b64": "$JSON_CONTENT",
    "app_was_running": $APP_RUNNING,
    "v_mags_data": $V_MAGS_JSON
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"