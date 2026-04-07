#!/bin/bash
echo "=== Exporting edge_on_halo_profiling results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# CCD Temperature
CURRENT_TEMP=$(indi_getprop -1 "CCD Simulator.CCD_TEMPERATURE.CCD_TEMPERATURE_VALUE" 2>/dev/null | tr -cd '0-9.\-' | head -c 10)
if [ -z "$CURRENT_TEMP" ]; then CURRENT_TEMP="999"; fi

# FITS info
FITS_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Images/ngc891'
files = []
for d in ['v_band_highres', 'l_band_binned']:
    dirpath = os.path.join(base, d)
    for ext in ['*.fits', '*.fit']:
        for f in glob.glob(os.path.join(dirpath, ext)):
            try:
                stat = os.stat(f)
                xbin = -1
                ybin = -1
                filt = ''
                temp = 999.0
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        xbin = int(h.get('XBINNING', -1))
                        ybin = int(h.get('YBINNING', -1))
                        filt = str(h.get('FILTER', '')).strip()
                        temp = float(h.get('CCD-TEMP', 999.0))
                except:
                    pass
                files.append({
                    'name': os.path.basename(f),
                    'dir': d,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'xbin': xbin,
                    'ybin': ybin,
                    'filter': filt,
                    'temp': temp
                })
            except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Sky capture
SKY_EXISTS="false"
if [ -f "/home/ga/Images/ngc891/sky_view_ngc891.png" ]; then
    SKY_MTIME=$(stat -c %Y "/home/ga/Images/ngc891/sky_view_ngc891.png" 2>/dev/null || echo "0")
    if [ "$SKY_MTIME" -gt "$TASK_START" ]; then
        SKY_EXISTS="true"
    fi
fi

# Log file
LOG_PATH="/home/ga/Documents/ngc891_observation_log.txt"
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

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "current_temp": "$CURRENT_TEMP",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_EXISTS_PY,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="