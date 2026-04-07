#!/bin/bash
echo "=== Exporting asteroid_lightcurve_photometry results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 4. Get current filter slot
CURRENT_FILTER=$(indi_getprop -1 "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE" 2>/dev/null | tr -cd '0-9' | head -c 3)
if [ -z "$CURRENT_FILTER" ]; then CURRENT_FILTER="-1"; fi

# 5. Check directory and FITS files
UPLOAD_DIR="/home/ga/Images/lightcurves/nysa"
DIR_EXISTS="false"
if [ -d "$UPLOAD_DIR" ]; then
    DIR_EXISTS="true"
fi

FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$UPLOAD_DIR/**/*.fits', '$UPLOAD_DIR/**/*.fit', '$UPLOAD_DIR/*.fits', '$UPLOAD_DIR/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                files.append({
                    'name': os.path.basename(f),
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass
except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 6. Check ALCDEF report
REPORT_PATH="/home/ga/Documents/nysa_lightcurve.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 200 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DIR_EXISTS_PY=$([ "$DIR_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# 7. Create JSON result
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "current_filter_slot": $CURRENT_FILTER,
    "dir_exists": $DIR_EXISTS_PY,
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="