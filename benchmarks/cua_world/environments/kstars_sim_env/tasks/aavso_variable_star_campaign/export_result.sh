#!/bin/bash
echo "=== Exporting aavso_variable_star_campaign results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 2. Get current telescope position ─────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# ── 3. Get current filter slot ────────────────────────────────────────
CURRENT_FILTER=$(indi_getprop -1 "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE" 2>/dev/null | tr -cd '0-9' | head -c 3)
if [ -z "$CURRENT_FILTER" ]; then CURRENT_FILTER="-1"; fi

# ── 4. Count FITS files in expected directory ─────────────────────────
FITS_DIR="/home/ga/Images/sscyg/session1"
FITS_COUNT=0
FITS_FILES_INFO="[]"

if [ -d "$FITS_DIR" ]; then
    FITS_COUNT=$(find "$FITS_DIR" -maxdepth 2 -name "*.fits" -o -name "*.fit" | wc -l)

    FITS_FILES_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$FITS_DIR/**/*.fits', '$FITS_DIR/**/*.fit', '$FITS_DIR/*.fits', '$FITS_DIR/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                files.append({'name': os.path.basename(f), 'path': f, 'size': stat.st_size, 'mtime': stat.st_mtime})
            except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")
fi

# Also check for any FITS anywhere in sscyg directory tree
FITS_TOTAL=$(find /home/ga/Images/sscyg 2>/dev/null -name "*.fits" -o -name "*.fit" | wc -l)

# ── 5. Check for sky capture image ────────────────────────────────────
SKY_CAPTURE_EXISTS="false"
SKY_CAPTURE_PATH=""
if find /home/ga/ -maxdepth 4 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | grep -qi "sky\|capture\|field\|view"; then
    SKY_CAPTURE_EXISTS="true"
fi
# Check the default sky capture output
if [ -f /home/ga/sky_view.png ] || [ -f /home/ga/Images/sky_view.png ]; then
    SKY_CAPTURE_EXISTS="true"
fi

# ── 6. Check report file ──────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/aavso_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 7. Extract FITS header info for filter verification ───────────────
FITS_FILTER_USED=""
FIRST_FITS=$(find "$FITS_DIR" -name "*.fits" 2>/dev/null | head -1)
if [ -n "$FIRST_FITS" ]; then
    FITS_FILTER_USED=$(python3 -c "
try:
    from astropy.io import fits
    with fits.open('$FIRST_FITS') as hdul:
        h = hdul[0].header
        print(h.get('FILTER', h.get('FILTER2', '')))
except Exception as e:
    print('')
" 2>/dev/null || echo "")
fi

# ── 8. Get task start time ────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 9. Write result JSON ──────────────────────────────────────────────
# Convert shell booleans to Python booleans for heredoc interpolation
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
    "fits_count_session": $FITS_COUNT,
    "fits_count_total": $FITS_TOTAL,
    "fits_files": $FITS_FILES_INFO,
    "sky_capture_exists": $SKY_CAPTURE_EXISTS_PY,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64",
    "fits_filter_used": "$FITS_FILTER_USED"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="
cat /tmp/task_result.json
