#!/bin/bash
echo "=== Exporting ccd_focus_calibration results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 2. Get current device properties ──────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

FINAL_FOCUS=$(indi_getprop -1 "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION" 2>/dev/null | tr -cd '0-9' | head -c 8)
if [ -z "$FINAL_FOCUS" ]; then FINAL_FOCUS="-1"; fi

# ── 3. Count FITS files ───────────────────────────────────────────────
FITS_DIR="/home/ga/Images/focus_run"
FITS_INFO=$(python3 -c "
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

# ── 4. Check report file ──────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/focus_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 5. Get task start time ────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# ── 6. Write result JSON ──────────────────────────────────────────────
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "final_focus": $FINAL_FOCUS,
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="