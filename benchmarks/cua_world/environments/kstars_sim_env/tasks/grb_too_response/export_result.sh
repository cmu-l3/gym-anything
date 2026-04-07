#!/bin/bash
echo "=== Exporting grb_too_response results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 3. Get current filter slot
CURRENT_FILTER=$(indi_getprop -1 "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE" 2>/dev/null | tr -cd '0-9' | head -c 3)
if [ -z "$CURRENT_FILTER" ]; then CURRENT_FILTER="-1"; fi

# 4. Extract FITS files metadata
FITS_INFO=$(python3 -c "
import os, json, glob

base_dir = '/home/ga/Images/grb/221009A'
files = []

# Scan confirmation and science dirs, as well as root
dirs_to_scan = [
    ('confirmation', os.path.join(base_dir, 'confirmation')),
    ('science', os.path.join(base_dir, 'science')),
    ('root', base_dir)
]

for phase, d in dirs_to_scan:
    if not os.path.exists(d): continue
    for pattern in [os.path.join(d, '*.fits'), os.path.join(d, '*.fit')]:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                exptime = -1.0
                filt = ''
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        exptime = float(h.get('EXPTIME', -1))
                        filt = str(h.get('FILTER', h.get('FILTER2', ''))).strip()
                except: pass
                
                files.append({
                    'name': os.path.basename(f),
                    'dir': phase,
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'exptime': exptime,
                    'filter': filt
                })
            except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 5. Check Sky View
SKY_VIEW_PATH="/home/ga/Images/grb/221009A/sky_view.png"
SKY_VIEW_EXISTS="false"
SKY_VIEW_SIZE=0
if [ -f "$SKY_VIEW_PATH" ]; then
    SKY_VIEW_MTIME=$(stat -c %Y "$SKY_VIEW_PATH" 2>/dev/null || echo "0")
    if [ "$SKY_VIEW_MTIME" -gt "$TASK_START" ]; then
        SKY_VIEW_EXISTS="true"
        SKY_VIEW_SIZE=$(stat -c %s "$SKY_VIEW_PATH" 2>/dev/null || echo "0")
    fi
fi

# 6. Check GCN Circular Report
REPORT_PATH="/home/ga/Documents/gcn_circular.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# 7. Write Result JSON
SKY_VIEW_EXISTS_PY=$([ "$SKY_VIEW_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "current_filter_slot": $CURRENT_FILTER,
    "fits_files": $FITS_INFO,
    "sky_view_exists": $SKY_VIEW_EXISTS_PY,
    "sky_view_size": $SKY_VIEW_SIZE,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="