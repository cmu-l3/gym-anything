#!/bin/bash
echo "=== Exporting wolf_rayet_bubble_survey results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASE_DIR="/home/ga/Images/WR_survey"

# 1. Collect comprehensive FITS information using Python
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$BASE_DIR'
files = []

# Scan all FITS files recursively
pattern = os.path.join(base, '**', '*.fits')
for f in glob.glob(pattern, recursive=True):
    try:
        stat = os.stat(f)
        filt = 'Unknown'
        exptime = -1.0
        try:
            from astropy.io import fits as pyfits
            with pyfits.open(f) as hdul:
                h = hdul[0].header
                hf = str(h.get('FILTER', '')).strip()
                if hf:
                    filt = hf
                exptime = float(h.get('EXPTIME', -1))
        except: 
            pass
            
        # Parse path to get logical target and directory filter
        rel_path = os.path.relpath(f, base)
        parts = rel_path.split(os.sep)
        target = parts[0] if len(parts) > 0 else 'Unknown'
        dir_filter = parts[1] if len(parts) > 1 else 'Unknown'

        files.append({
            'name': os.path.basename(f), 
            'path': f,
            'target_dir': target,
            'filter_dir': dir_filter,
            'header_filter': filt, 
            'exptime': exptime,
            'size': stat.st_size, 
            'mtime': stat.st_mtime
        })
    except Exception as e:
        pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 2. Check for the generated sky views
PNG_INFO=$(python3 -c "
import os, json, glob
base = '$BASE_DIR'
files = []
pattern = os.path.join(base, '**', '*.png')
for f in glob.glob(pattern, recursive=True):
    try:
        stat = os.stat(f)
        rel_path = os.path.relpath(f, base)
        parts = rel_path.split(os.sep)
        target = parts[0] if len(parts) > 0 else 'Unknown'
        files.append({
            'name': os.path.basename(f),
            'target_dir': target,
            'size': stat.st_size,
            'mtime': stat.st_mtime
        })
    except:
        pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Check markdown report
REPORT_PATH="/home/ga/Documents/wr_survey_report.md"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# 4. Generate JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "png_files": $PNG_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="