#!/bin/bash
echo "=== Exporting oseti_high_cadence_subframing results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Get telescope final position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

UPLOAD_DIR="/home/ga/Images/oseti/kic8462852"

# 2. Extract FITS metrics using astropy
# Checks NAXIS1/2 for Subframing and EXPTIME for Cadence verification
FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$UPLOAD_DIR/*.fits', '$UPLOAD_DIR/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                naxis1 = naxis2 = -1
                exptime = -1.0
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        naxis1 = int(h.get('NAXIS1', -1))
                        naxis2 = int(h.get('NAXIS2', -1))
                        exptime = float(h.get('EXPTIME', -1.0))
                except: pass
                files.append({
                    'name': os.path.basename(f),
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'naxis1': naxis1,
                    'naxis2': naxis2,
                    'exptime': exptime
                })
            except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Check for sky capture existence and freshness
SKY_EXISTS="false"
if [ -f "$UPLOAD_DIR/reference_sky.png" ]; then
    SKY_MTIME=$(stat -c %Y "$UPLOAD_DIR/reference_sky.png" 2>/dev/null || echo "0")
    [ "$SKY_MTIME" -gt "$TASK_START" ] && SKY_EXISTS="true"
fi

# 4. Check observation log
LOG_PATH="/home/ga/Documents/oseti_observation_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0
LOG_B64=""
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_B64=$(head -n 50 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

# 5. Export JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_EXISTS_PY,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json.")
PYEOF

echo "=== Export complete ==="