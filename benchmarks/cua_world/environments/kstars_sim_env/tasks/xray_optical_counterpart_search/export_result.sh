#!/bin/bash
echo "=== Exporting xray_optical_counterpart_search results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASE_DIR="/home/ga/Images/xray_followup"

# Collect FITS info via Python to safely parse headers
FITS_INFO=$(python3 -c "
import os, json, glob
base = '$BASE_DIR'
files = []
for pattern in [base + '/**/*.fits', base + '/**/*.fit']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            filt = ''
            ra_str = ''
            dec_str = ''
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    filt = str(h.get('FILTER', '')).strip()
                    ra_str = str(h.get('OBJCTRA', '')).strip()
                    dec_str = str(h.get('OBJCTDEC', '')).strip()
            except: pass
            files.append({
                'name': os.path.basename(f),
                'path': f,
                'dir': os.path.basename(os.path.dirname(f)),
                'size': stat.st_size,
                'mtime': stat.st_mtime,
                'filter': filt,
                'ra_str': ra_str,
                'dec_str': dec_str
            })
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Collect PNG reference maps
PNG_INFO=$(python3 -c "
import os, json, glob
base = '$BASE_DIR'
files = []
for f in glob.glob(base + '/**/*.png', recursive=True):
    try:
        stat = os.stat(f)
        files.append({
            'name': os.path.basename(f),
            'path': f,
            'dir': os.path.basename(os.path.dirname(f)),
            'size': stat.st_size,
            'mtime': stat.st_mtime
        })
    except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

REPORT_PATH="/home/ga/Documents/optical_followup_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

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

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="