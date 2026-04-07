#!/bin/bash
echo "=== Exporting service_queue_execution results ==="

source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Query final coordinates to verify last slew
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# Process subdirectories and FITS files programmatically via Python
FITS_INFO=$(python3 -c "
import os, json, glob
base = '/home/ga/Images/queue'
files = []
for subdir in ['m44', 'ngc2392', 'm51']:
    d = os.path.join(base, subdir)
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

# Evaluate Sky Capture Status
SKY_CAPTURE_EXISTS="false"
SKY_CAPTURE_SIZE="0"
if [ -f "/home/ga/Images/queue/final_sky.png" ]; then
    SKY_MTIME=$(stat -c %Y "/home/ga/Images/queue/final_sky.png" 2>/dev/null || echo "0")
    if [ "$SKY_MTIME" -gt "$TASK_START" ]; then
        SKY_CAPTURE_EXISTS="true"
        SKY_CAPTURE_SIZE=$(stat -c %s "/home/ga/Images/queue/final_sky.png" 2>/dev/null || echo "0")
    fi
fi

# Evaluate Session Log content
LOG_EXISTS="false"
LOG_MTIME="0"
LOG_B64=""
if [ -f "/home/ga/Documents/session_log.txt" ]; then
    LOG_MTIME=$(stat -c %Y "/home/ga/Documents/session_log.txt" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_EXISTS="true"
        LOG_B64=$(head -n 50 "/home/ga/Documents/session_log.txt" | base64 -w 0 2>/dev/null || echo "")
    fi
fi

SKY_CAPTURE_EXISTS_PY=$([ "$SKY_CAPTURE_EXISTS" = "true" ] && echo "True" || echo "False")
LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

# Generate structured JSON for the verifier script
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_CAPTURE_EXISTS_PY,
    "sky_capture_size": $SKY_CAPTURE_SIZE,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="