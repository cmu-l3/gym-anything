#!/bin/bash
echo "=== Exporting exoplanet_transit_photometry results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 2. Get current telescope position ─────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# ── 3. Get current filter slot & focuser position ─────────────────────
CURRENT_FILTER=$(indi_getprop -1 "Filter Simulator.FILTER_SLOT.FILTER_SLOT_VALUE" 2>/dev/null | tr -cd '0-9' | head -c 3)
if [ -z "$CURRENT_FILTER" ]; then CURRENT_FILTER="-1"; fi

CURRENT_FOCUS=$(indi_getprop -1 "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION" 2>/dev/null | tr -cd '0-9.' | head -c 10)
if [ -z "$CURRENT_FOCUS" ]; then CURRENT_FOCUS="-1"; fi

# ── 4. Collect FITS files info ────────────────────────────────────────
FITS_DIR="/home/ga/Images/transits/hd189733b"
FITS_FILES_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$FITS_DIR/**/*.fits', '$FITS_DIR/**/*.fit', '$FITS_DIR/*.fits', '$FITS_DIR/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                filt = ''
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        hf = str(h.get('FILTER', '')).strip()
                        if hf:
                            filt = hf
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({'name': os.path.basename(f), 'path': f, 
                              'size': stat.st_size, 'mtime': stat.st_mtime,
                              'filter': filt, 'exptime': exptime})
            except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 5. Check for sky capture image ────────────────────────────────────
SKY_CAPTURE_EXISTS="false"
SKY_CAPTURE_MTIME=0
if [ -f "$FITS_DIR/sky_view.png" ]; then
    SKY_CAPTURE_EXISTS="true"
    SKY_CAPTURE_MTIME=$(stat -c %Y "$FITS_DIR/sky_view.png" 2>/dev/null || echo "0")
fi

# ── 6. Check report file ──────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/transit_log.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(head -n 200 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 7. Get task start time ────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 8. Write result JSON ──────────────────────────────────────────────
SKY_CAPTURE_EXISTS_PY=$([ "$SKY_CAPTURE_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json, os

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "current_filter_slot": $CURRENT_FILTER,
    "current_focus": "$CURRENT_FOCUS",
    "fits_files": $FITS_FILES_INFO,
    "sky_capture_exists": $SKY_CAPTURE_EXISTS_PY,
    "sky_capture_mtime": $SKY_CAPTURE_MTIME,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="