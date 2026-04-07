#!/bin/bash
echo "=== Exporting carbon_star_color_index_survey results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASE_DIR="/home/ga/Images/carbon_lab"

# Collect FITS info and PNG info per target
FILE_INFO=$(python3 -c "
import os, json, glob

base = '$BASE_DIR'
targets = ['R_Leporis', 'T_Lyrae', 'V_Aquilae', 'W_Orionis', 'U_Hydrae']
files = []

for target in targets:
    d = os.path.join(base, target)
    if not os.path.exists(d): continue
    
    # FITS files
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                filt = ''
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        filt = str(h.get('FILTER', '')).strip()
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({
                    'name': os.path.basename(f),
                    'target': target,
                    'type': 'fits',
                    'filter': filt,
                    'exptime': exptime,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass
            
    # PNG files
    for f in glob.glob(d + '/*.png'):
        try:
            stat = os.stat(f)
            files.append({
                'name': os.path.basename(f),
                'target': target,
                'type': 'png',
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
        except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Read CSV report
CSV_PATH="/home/ga/Documents/lab_summary.csv"
CSV_EXISTS="false"
CSV_MTIME=0
CSV_CONTENT_B64=""
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_CONTENT_B64=$(head -n 20 "$CSV_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

CSV_EXISTS_PY=$([ "$CSV_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "files": $FILE_INFO,
    "csv_exists": $CSV_EXISTS_PY,
    "csv_mtime": $CSV_MTIME,
    "csv_content_b64": "$CSV_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="