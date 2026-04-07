#!/bin/bash
echo "=== Exporting reflection_nebula_polarimetry results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screen state
take_screenshot /tmp/task_final.png

# 2. Extract timestamp limits
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Read telescope coordinates
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 4. Extract detailed FITS information using Python
FITS_INFO=$(python3 -c "
import os, json, glob

base_dir = '/home/ga/Images/polarimetry/M78'
dirs = ['angle_000', 'angle_045', 'angle_090', 'angle_135']
files = []

for d in dirs:
    path = os.path.join(base_dir, d)
    for pattern in [path + '/*.fits', path + '/*.fit']:
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
                    'dir': d,
                    'filter': filt,
                    'exptime': exptime,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except Exception:
                pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 5. Check Context Image
CONTEXT_IMAGE="/home/ga/Images/polarimetry/M78/m78_context.png"
CONTEXT_EXISTS="false"
CONTEXT_MTIME=0
CONTEXT_SIZE=0
if [ -f "$CONTEXT_IMAGE" ]; then
    CONTEXT_MTIME=$(stat -c %Y "$CONTEXT_IMAGE" 2>/dev/null || echo "0")
    CONTEXT_SIZE=$(stat -c %s "$CONTEXT_IMAGE" 2>/dev/null || echo "0")
    if [ "$CONTEXT_MTIME" -gt "$TASK_START" ]; then
        CONTEXT_EXISTS="true"
    fi
fi

# 6. Check Observation Log
LOG_PATH="/home/ga/Documents/stokes_observation_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0
LOG_B64=""
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_B64=$(head -n 50 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# Prepare booleans for Python template injection
CONTEXT_EXISTS_PY=$([ "$CONTEXT_EXISTS" = "true" ] && echo "True" || echo "False")
LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

# 7. Write Result JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "context_image_exists": $CONTEXT_EXISTS_PY,
    "context_image_size": $CONTEXT_SIZE,
    "context_image_mtime": $CONTEXT_MTIME,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="