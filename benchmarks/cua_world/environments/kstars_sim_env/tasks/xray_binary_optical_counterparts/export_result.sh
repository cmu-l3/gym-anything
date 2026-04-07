#!/bin/bash
echo "=== Exporting xray_binary_optical_counterparts results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS info per target directory
FITS_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Images/xray_followup'
files = []
for pattern in [base + '/**/*.fits', base + '/**/*.fit']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            exptime = -1
            filt = ''
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    filt = str(h.get('FILTER', '')).strip()
                    exptime = float(h.get('EXPTIME', -1))
            except: pass
            files.append({
                'name': os.path.basename(f),
                'dir': os.path.basename(os.path.dirname(f)),
                'filter': filt,
                'exptime': exptime,
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check finding charts
CHARTS_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Images/xray_followup'
files = []
for pattern in [base + '/**/finding_chart.png']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            files.append({
                'name': os.path.basename(f),
                'dir': os.path.basename(os.path.dirname(f)),
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check Summary Report
REPORT_PATH="/home/ga/Documents/xray_followup_report.txt"
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
    "charts": $CHARTS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="