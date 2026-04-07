#!/bin/bash
echo "=== Exporting microlensing_caustic_crossing results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 2. Get current telescope state ────────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

PARK_STATE=$(indi_getprop -1 "Telescope Simulator.TELESCOPE_PARK.PARK" 2>/dev/null)
UNPARK_STATE=$(indi_getprop -1 "Telescope Simulator.TELESCOPE_PARK.UNPARK" 2>/dev/null)
TRACK_STATE=$(indi_getprop -1 "Telescope Simulator.ON_COORD_SET.TRACK" 2>/dev/null)

# ── 3. Count FITS files in expected directory ─────────────────────────
FITS_DIR="/home/ga/Images/microlensing/OGLE-2026-BLG-0042"
FITS_FILES_INFO="[]"

if [ -d "$FITS_DIR" ]; then
    FITS_FILES_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$FITS_DIR/*.fits', '$FITS_DIR/*.fit']:
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
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'filter': filt,
                    'exptime': exptime
                })
            except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")
fi

# ── 4. Check for sky capture image ────────────────────────────────────
SKY_CAPTURE_EXISTS="false"
if [ -f "$FITS_DIR/sky_field.png" ]; then
    SKY_CAPTURE_EXISTS="true"
fi

# ── 5. Check report file ──────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/microlensing_response.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 6. Get task start time ────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 7. Write result JSON ──────────────────────────────────────────────
SKY_CAPTURE_EXISTS_PY=$([ "$SKY_CAPTURE_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json, os

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "park_state": "$PARK_STATE",
    "unpark_state": "$UNPARK_STATE",
    "track_state": "$TRACK_STATE",
    "fits_files": $FITS_FILES_INFO,
    "sky_capture_exists": $SKY_CAPTURE_EXISTS_PY,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="