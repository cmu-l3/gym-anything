#!/bin/bash
echo "=== Exporting virgo_sn_patrol results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 1. Get telescope position ─────────────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# ── 2. Scan for FITS files ────────────────────────────────────────────
PATROL_BASE="/home/ga/Images/patrol/virgo"
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$PATROL_BASE'
files = []

for target in ['M87', 'M84', 'M100', 'M49']:
    d = os.path.join(base, target)
    if os.path.isdir(d):
        for pattern in [d + '/*.fits', d + '/*.fit']:
            for f in glob.glob(pattern):
                try:
                    stat = os.stat(f)
                    files.append({
                        'name': os.path.basename(f),
                        'target': target,
                        'size': stat.st_size,
                        'mtime': stat.st_mtime
                    })
                except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 3. Check for subdirectories ───────────────────────────────────────
DIR_M87=$([ -d "$PATROL_BASE/M87" ] && echo "true" || echo "false")
DIR_M84=$([ -d "$PATROL_BASE/M84" ] && echo "true" || echo "false")
DIR_M100=$([ -d "$PATROL_BASE/M100" ] && echo "true" || echo "false")
DIR_M49=$([ -d "$PATROL_BASE/M49" ] && echo "true" || echo "false")

# ── 4. Check for sky capture ──────────────────────────────────────────
SKY_EXISTS="false"
SKY_MTIME=0
if [ -n "$(find /home/ga/Images /home/ga -maxdepth 4 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | grep -i 'sky\|capture\|virgo')" ]; then
    SKY_EXISTS="true"
fi
if [ -f "$PATROL_BASE/sky_view.png" ]; then
    SKY_EXISTS="true"
fi
if [ -f "/home/ga/Images/captures/sky_capture_*.png" ]; then
    SKY_EXISTS="true"
fi

# ── 5. Check patrol log ───────────────────────────────────────────────
LOG_PATH="$PATROL_BASE/patrol_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0
LOG_B64=""
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_B64=$(head -n 100 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DIR_M87_PY=$([ "$DIR_M87" = "true" ] && echo "True" || echo "False")
DIR_M84_PY=$([ "$DIR_M84" = "true" ] && echo "True" || echo "False")
DIR_M100_PY=$([ "$DIR_M100" = "true" ] && echo "True" || echo "False")
DIR_M49_PY=$([ "$DIR_M49" = "true" ] && echo "True" || echo "False")
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "dirs": {
        "M87": $DIR_M87_PY,
        "M84": $DIR_M84_PY,
        "M100": $DIR_M100_PY,
        "M49": $DIR_M49_PY
    },
    "sky_capture_exists": $SKY_EXISTS_PY,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="