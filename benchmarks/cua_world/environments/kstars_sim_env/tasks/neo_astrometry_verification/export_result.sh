#!/bin/bash
echo "=== Exporting neo_astrometry_verification results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# Collect FITS info
UPLOAD_DIR="/home/ga/Images/asteroids/2020QG"
FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$UPLOAD_DIR/**/*.fits', '$UPLOAD_DIR/**/*.fit', '$UPLOAD_DIR/*.fits', '$UPLOAD_DIR/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                files.append({'name': os.path.basename(f), 'path': f,
                               'size': stat.st_size, 'mtime': stat.st_mtime})
            except: pass
except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check sky capture
SKY_EXISTS="false"
if [ -f "/home/ga/Images/asteroids/2020QG/sky_field.png" ]; then
    SKY_MTIME=$(stat -c %Y "/home/ga/Images/asteroids/2020QG/sky_field.png" 2>/dev/null || echo "0")
    [ "$SKY_MTIME" -gt "$TASK_START" ] && SKY_EXISTS="true"
fi

# Check MPC report
REPORT_PATH="/home/ga/Documents/mpc_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_EXISTS_PY,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="
