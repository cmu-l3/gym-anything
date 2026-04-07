#!/bin/bash
echo "=== Exporting lsb_galaxy_deep_imaging results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 1. Query current INDI state ───────────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

COOLER_ON_VAL=$(indi_getprop -1 "CCD Simulator.CCD_COOLER.COOLER_ON" 2>/dev/null || echo "")
if [ "$COOLER_ON_VAL" = "On" ]; then
    COOLER_ON="true"
else
    COOLER_ON="false"
fi

CURRENT_TEMP=$(indi_getprop -1 "CCD Simulator.CCD_TEMPERATURE.CCD_TEMPERATURE_VALUE" 2>/dev/null | tr -cd '0-9.\-' | head -c 10)
if [ -z "$CURRENT_TEMP" ]; then CURRENT_TEMP="999"; fi

# ── 2. Parse FITS files ───────────────────────────────────────────────
UPLOAD_DIR="/home/ga/Images/lsb/malin1"

FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$UPLOAD_DIR/*.fits', '$UPLOAD_DIR/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                exptime = -1.0
                ccd_temp = 999.0
                xbin = 1
                ybin = 1
                filt = ''
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        exptime = float(h.get('EXPTIME', -1))
                        ccd_temp = float(h.get('CCD-TEMP', 999.0))
                        xbin = int(h.get('XBINNING', 1))
                        ybin = int(h.get('YBINNING', 1))
                        filt = str(h.get('FILTER', '')).strip()
                except Exception as e:
                    pass
                    
                files.append({
                    'name': os.path.basename(f),
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'exptime': exptime,
                    'ccd_temp': ccd_temp,
                    'xbin': xbin,
                    'ybin': ybin,
                    'filter': filt
                })
            except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 3. Check artifacts ────────────────────────────────────────────────
SKY_PATH="$UPLOAD_DIR/malin1_sky.png"
SKY_EXISTS="false"
if [ -f "$SKY_PATH" ]; then
    SKY_MTIME=$(stat -c %Y "$SKY_PATH" 2>/dev/null || echo "0")
    if [ "$SKY_MTIME" -gt "$TASK_START" ]; then SKY_EXISTS="true"; fi
fi

REPORT_PATH="/home/ga/Documents/malin1_report.txt"
REPORT_EXISTS="false"
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then 
        REPORT_EXISTS="true"
        REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
    fi
fi

COOLER_ON_PY=$([ "$COOLER_ON" = "true" ] && echo "True" || echo "False")
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "cooler_on": $COOLER_ON_PY,
    "current_temp": "$CURRENT_TEMP",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_EXISTS_PY,
    "report_exists": $REPORT_EXISTS_PY,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="