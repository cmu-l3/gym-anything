#!/bin/bash
echo "=== Exporting interstellar_object_rapid_acquisition results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# Collect FITS info
FITS_DIR="/home/ga/Images/ISO_C2026"
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$FITS_DIR'
files = []
for pattern in [base + '/*.fits', base + '/*.fit']:
    for f in glob.glob(pattern):
        try:
            stat = os.stat(f)
            xbin, ybin, exptime, filt = 1, 1, -1.0, ''
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    xbin = int(h.get('XBINNING', 1))
                    ybin = int(h.get('YBINNING', 1))
                    exptime = float(h.get('EXPTIME', -1.0))
                    hf = str(h.get('FILTER', '')).strip()
                    if hf: filt = hf
            except: pass
            files.append({
                'name': os.path.basename(f),
                'mtime': stat.st_mtime,
                'size': stat.st_size,
                'xbinning': xbin,
                'ybinning': ybin,
                'exptime': exptime,
                'filter': filt
            })
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check thermal proxy
PROXY_EXISTS="false"
PROXY_MTIME=0
if [ -f "$FITS_DIR/thermal_proxy.png" ]; then
    PROXY_MTIME=$(stat -c %Y "$FITS_DIR/thermal_proxy.png" 2>/dev/null || echo "0")
    if [ "$PROXY_MTIME" -gt "$TASK_START" ]; then
        PROXY_EXISTS="true"
    fi
fi

# Check report
REPORT_PATH="/home/ga/Documents/iso_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

PROXY_EXISTS_PY=$([ "$PROXY_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "proxy_exists": $PROXY_EXISTS_PY,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="