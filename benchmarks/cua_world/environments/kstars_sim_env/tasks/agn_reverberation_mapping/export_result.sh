#!/bin/bash
echo "=== Exporting agn_reverberation_mapping results ==="

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

# 4. Collect FITS info from target directories
BASE_DIR="/home/ga/Images/reverb/ngc4151"
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$BASE_DIR'
files = []
for subdir in ['V', 'Ha']:
    d = os.path.join(base, subdir)
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                filt = subdir
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        hf = str(h.get('FILTER', '')).strip()
                        if hf: filt = hf
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({
                    'name': os.path.basename(f), 
                    'dir': subdir,
                    'filter': filt, 
                    'exptime': exptime,
                    'size': stat.st_size, 
                    'mtime': stat.st_mtime
                })
            except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 5. Check reference sky capture
REF_PATH="$BASE_DIR/reference_fov.png"
REF_EXISTS="false"
REF_MTIME=0
if [ -f "$REF_PATH" ]; then
    REF_MTIME=$(stat -c %Y "$REF_PATH" 2>/dev/null || echo "0")
    if [ "$REF_MTIME" -gt "$TASK_START" ]; then
        REF_EXISTS="true"
    fi
fi

# 6. Check Observation Log
LOG_PATH="/home/ga/Documents/ngc4151_obs_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0
LOG_B64=""
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_B64=$(head -n 50 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# Convert booleans for python template
REF_EXISTS_PY=$([ "$REF_EXISTS" = "true" ] && echo "True" || echo "False")
LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

# 7. Write result JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "reference_exists": $REF_EXISTS_PY,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="