#!/bin/bash
echo "=== Exporting finding_chart_atlas results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

CHART_DIR="/home/ga/Images/finding_charts"

# Collect PNGs info
PNGS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for f in glob.glob('$CHART_DIR/*.png'):
        try:
            stat = os.stat(f)
            files.append({'name': os.path.basename(f), 'path': f,
                           'size': stat.st_size, 'mtime': stat.st_mtime})
        except: pass
except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check atlas index
INDEX_PATH="$CHART_DIR/atlas_index.txt"
INDEX_EXISTS="false"
INDEX_MTIME=0
INDEX_B64=""
if [ -f "$INDEX_PATH" ]; then
    INDEX_EXISTS="true"
    INDEX_MTIME=$(stat -c %Y "$INDEX_PATH" 2>/dev/null || echo "0")
    INDEX_B64=$(head -n 50 "$INDEX_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

INDEX_EXISTS_PY=$([ "$INDEX_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "png_files": $PNGS_INFO,
    "index_exists": $INDEX_EXISTS_PY,
    "index_mtime": $INDEX_MTIME,
    "index_b64": "$INDEX_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="