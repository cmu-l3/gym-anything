#!/bin/bash
echo "=== Exporting remote_observatory_fault_recovery results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 1. Query INDI Device States ────────────────────────────────────────
TEL_CONN=$(indi_getprop -1 "Telescope Simulator.CONNECTION.CONNECT" 2>/dev/null || echo "Off")
CCD_CONN=$(indi_getprop -1 "CCD Simulator.CONNECTION.CONNECT" 2>/dev/null || echo "Off")
FIL_CONN=$(indi_getprop -1 "Filter Simulator.CONNECTION.CONNECT" 2>/dev/null || echo "Off")

TEL_PARK=$(indi_getprop -1 "Telescope Simulator.TELESCOPE_PARK.PARK" 2>/dev/null || echo "On")
FOCUS_POS=$(indi_getprop -1 "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION" 2>/dev/null | tr -cd '0-9' || echo "99000")
if [ -z "$FOCUS_POS" ]; then FOCUS_POS="99000"; fi

FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# ── 2. Check FITS Files ────────────────────────────────────────────────
VERIFICATION_DIR="/home/ga/Images/verification"
FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$VERIFICATION_DIR/**/*.fits', '$VERIFICATION_DIR/**/*.fit', '$VERIFICATION_DIR/*.fits', '$VERIFICATION_DIR/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                files.append({'name': os.path.basename(f), 'path': f,
                               'size': stat.st_size, 'mtime': stat.st_mtime})
            except: pass
except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 3. Check Resolution Report ─────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/fault_resolution.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 4. Generate JSON Output ────────────────────────────────────────────
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "tel_connected": "$TEL_CONN",
    "ccd_connected": "$CCD_CONN",
    "filter_connected": "$FIL_CONN",
    "tel_parked": "$TEL_PARK",
    "focus_position": $FOCUS_POS,
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="