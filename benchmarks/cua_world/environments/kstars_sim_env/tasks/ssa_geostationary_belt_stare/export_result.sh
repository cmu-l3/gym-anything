#!/bin/bash
echo "=== Exporting ssa_geostationary_belt_stare results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 1. Get current tracking state directly from INDI ───────────────────
TRACKING_STATE=$(indi_getprop -1 "Telescope Simulator.ON_COORD_SET.TRACK" 2>/dev/null || echo "Unknown")

# ── 2. Collect FITS files and extract RA from headers ──────────────────
UPLOAD_DIR="/home/ga/Images/SSA/geo_stare"
FITS_INFO=$(python3 -c "
import os, json, glob

files = []
d = '$UPLOAD_DIR'
for pattern in [d + '/*.fits', d + '/*.fit']:
    for f in glob.glob(pattern):
        try:
            stat = os.stat(f)
            filt = ''
            exptime = -1
            obj_ra = ''
            obj_dec = ''
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    hf = str(h.get('FILTER', '')).strip()
                    if hf: filt = hf
                    exptime = float(h.get('EXPTIME', -1))
                    obj_ra = str(h.get('OBJCTRA', h.get('RA', '')))
                    obj_dec = str(h.get('OBJCTDEC', h.get('DEC', '')))
            except Exception as e:
                pass
            files.append({
                'name': os.path.basename(f),
                'path': f,
                'filter': filt,
                'exptime': exptime,
                'ra': obj_ra,
                'dec': obj_dec,
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 3. Check Sky View Image ───────────────────────────────────────────
SKY_EXISTS="false"
SKY_PATH="$UPLOAD_DIR/sky_view.png"
if [ -f "$SKY_PATH" ]; then
    SKY_MTIME=$(stat -c %Y "$SKY_PATH" 2>/dev/null || echo "0")
    [ "$SKY_MTIME" -gt "$TASK_START" ] && SKY_EXISTS="true"
fi

# ── 4. Check SSA Report ───────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/ssa_report.txt"
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
    "indi_tracking_state": "$TRACKING_STATE",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_EXISTS_PY,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="