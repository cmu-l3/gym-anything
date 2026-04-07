#!/bin/bash
echo "=== Exporting wide_field_dark_nebula_survey results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASE="/home/ga/Images/survey"

# Collect detailed FITS info (including header extraction via astropy)
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$BASE'
files = []
for subdir in ['B33', 'B143', 'B86']:
    d = os.path.join(base, subdir)
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                focallen = -1.0
                aptdia = -1.0
                objra = ''
                objdec = ''
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        focallen = float(h.get('FOCALLEN', -1.0))
                        aptdia = float(h.get('APTDIA', -1.0))
                        objra = str(h.get('OBJCTRA', ''))
                        objdec = str(h.get('OBJCTDEC', ''))
                except: pass
                files.append({
                    'name': os.path.basename(f),
                    'dir': subdir,
                    'focallen': focallen,
                    'aptdia': aptdia,
                    'objra': objra,
                    'objdec': objdec,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Evaluate if contextual sky views were successfully captured
SKY_B33="false"; SKY_B143="false"; SKY_B86="false"
if [ -f "$BASE/B33/sky_view.png" ]; then
    [ "$(stat -c %Y "$BASE/B33/sky_view.png")" -gt "$TASK_START" ] && SKY_B33="true"
fi
if [ -f "$BASE/B143/sky_view.png" ]; then
    [ "$(stat -c %Y "$BASE/B143/sky_view.png")" -gt "$TASK_START" ] && SKY_B143="true"
fi
if [ -f "$BASE/B86/sky_view.png" ]; then
    [ "$(stat -c %Y "$BASE/B86/sky_view.png")" -gt "$TASK_START" ] && SKY_B86="true"
fi

# Evaluate survey log file
LOG_EXISTS="false"
LOG_B64=""
LOG_PATH="/home/ga/Documents/survey_log.txt"
if [ -f "$LOG_PATH" ]; then
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_EXISTS="true"
        LOG_B64=$(head -n 50 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
    fi
fi

# Convert Bash boolean outputs to Python booleans for JSON substitution
SKY_B33_PY=$([ "$SKY_B33" = "true" ] && echo "True" || echo "False")
SKY_B143_PY=$([ "$SKY_B143" = "true" ] && echo "True" || echo "False")
SKY_B86_PY=$([ "$SKY_B86" = "true" ] && echo "True" || echo "False")
LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "sky_views": {
        "B33": $SKY_B33_PY,
        "B143": $SKY_B143_PY,
        "B86": $SKY_B86_PY
    },
    "log_exists": $LOG_EXISTS_PY,
    "log_b64": "$LOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="