#!/bin/bash
echo "=== Exporting telescope_collimation_star_test results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get telescope position and INDI properties
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

CURRENT_FILTER=$(indi_getprop -1 "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE" 2>/dev/null | tr -cd '0-9' | head -c 3)
if [ -z "$CURRENT_FILTER" ]; then CURRENT_FILTER="-1"; fi

CURRENT_FOCUS=$(indi_getprop -1 "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION" 2>/dev/null | tr -cd '0-9' | head -c 8)
if [ -z "$CURRENT_FOCUS" ]; then CURRENT_FOCUS="-1"; fi

# 3. Read Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Scrape output files
OUT_DIR="/home/ga/Maintenance/collimation_test"
FITS_FILES_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    if os.path.exists('$OUT_DIR'):
        for pattern in ['$OUT_DIR/*.fits', '$OUT_DIR/*.fit']:
            for f in glob.glob(pattern):
                try:
                    stat = os.stat(f)
                    files.append({
                        'name': os.path.basename(f),
                        'path': f,
                        'size': stat.st_size,
                        'mtime': stat.st_mtime
                    })
                except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 5. Check context image
CONTEXT_EXISTS="false"
CONTEXT_MTIME=0
CONTEXT_SIZE=0
if [ -f "$OUT_DIR/field_context.png" ]; then
    CONTEXT_EXISTS="true"
    CONTEXT_MTIME=$(stat -c %Y "$OUT_DIR/field_context.png" 2>/dev/null || echo "0")
    CONTEXT_SIZE=$(stat -c %s "$OUT_DIR/field_context.png" 2>/dev/null || echo "0")
fi

# 6. Check report text
REPORT_PATH="$OUT_DIR/report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

CONTEXT_EXISTS_PY=$([ "$CONTEXT_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# 7. Write result JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "current_filter_slot": $CURRENT_FILTER,
    "current_focuser_pos": $CURRENT_FOCUS,
    "fits_files": $FITS_FILES_INFO,
    "context_exists": $CONTEXT_EXISTS_PY,
    "context_mtime": $CONTEXT_MTIME,
    "context_size": $CONTEXT_SIZE,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="