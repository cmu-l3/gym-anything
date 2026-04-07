#!/bin/bash
echo "=== Exporting frb_host_galaxy_characterization results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# Extract FITS metadata from the target directory
TARGET_DIR="/home/ga/Images/FRB2024exq"
FITS_INFO=$(python3 -c "
import os, json, glob

files = []
d = '$TARGET_DIR'
for pattern in [d + '/*.fits', d + '/*.fit']:
    for f in glob.glob(pattern):
        try:
            stat = os.stat(f)
            filt = ''
            exptime = -1.0
            try:
                from astropy.io import fits
                with fits.open(f) as hdul:
                    h = hdul[0].header
                    filt = str(h.get('FILTER', h.get('FILTER2', ''))).strip()
                    exptime = float(h.get('EXPTIME', -1))
            except: pass
            
            files.append({
                'name': os.path.basename(f),
                'filter': filt,
                'exptime': exptime,
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check finding chart
CHART_PATH="$TARGET_DIR/finding_chart_cool.png"
CHART_EXISTS="false"
CHART_MTIME=0
CHART_SIZE=0
if [ -f "$CHART_PATH" ]; then
    CHART_EXISTS="true"
    CHART_MTIME=$(stat -c %Y "$CHART_PATH" 2>/dev/null || echo "0")
    CHART_SIZE=$(stat -c %s "$CHART_PATH" 2>/dev/null || echo "0")
fi

# Check status report
REPORT_PATH="/home/ga/Documents/frb_optical_status.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

CHART_EXISTS_PY=$([ "$CHART_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "chart_exists": $CHART_EXISTS_PY,
    "chart_mtime": $CHART_MTIME,
    "chart_size": $CHART_SIZE,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="