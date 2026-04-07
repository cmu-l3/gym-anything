#!/bin/bash
echo "=== Exporting lsb_galaxy_deep_survey results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Get telescope final position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 2. Extract FITS information
FITS_INFO=$(python3 -c "
import os, json, glob
base_dir = '/home/ga/Images/LSB_survey'
files = []
try:
    for pattern in [f'{base_dir}/**/*.fits', f'{base_dir}/**/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                frame_type = ''
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        frame_type = str(h.get('IMAGETYP', h.get('FRAME', ''))).strip().upper()
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({
                    'name': os.path.basename(f),
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'frame_type': frame_type,
                    'exptime': exptime
                })
            except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Check for sky views
SKY_VIEWS=$(python3 -c "
import os, json, glob
base_dir = '/home/ga/Images/LSB_survey/targets'
views = []
for f in glob.glob(f'{base_dir}/**/view.png', recursive=True):
    try:
        stat = os.stat(f)
        views.append({'path': f, 'mtime': stat.st_mtime})
    except: pass
print(json.dumps(views))
" 2>/dev/null || echo "[]")

# 4. Check Report
REPORT_PATH="/home/ga/Documents/lsb_survey_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# 5. Export JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "sky_views": $SKY_VIEWS,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="