#!/bin/bash
echo "=== Exporting robotic_too_pipeline_scripting results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Script properties
SCRIPT_PATH="/home/ga/too_capture.sh"
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    [ -x "$SCRIPT_PATH" ] && SCRIPT_EXECUTABLE="true"
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | base64 -w 0 2>/dev/null)
fi

# 2. Telescope parked state
PARK_STATE=$(indi_getprop -1 "Telescope Simulator.TELESCOPE_PARK.PARK" 2>/dev/null | tr -d '\n\r')

# 3. Target FITS files
UPLOAD_DIR="/home/ga/Images/too_alerts/GRB221009A"
FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for pattern in ['$UPLOAD_DIR/*.fits', '$UPLOAD_DIR/*.fit', '$UPLOAD_DIR/**/*.fits', '$UPLOAD_DIR/**/*.fit']:
        for f in glob.glob(pattern, recursive=True):
            try:
                stat = os.stat(f)
                exptime = -1.0
                filt = ''
                ra = ''
                dec = ''
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        exptime = float(h.get('EXPTIME', -1))
                        filt = str(h.get('FILTER', ''))
                        ra = str(h.get('OBJCTRA', ''))
                        dec = str(h.get('OBJCTDEC', ''))
                except Exception as e:
                    pass
                files.append({
                    'name': os.path.basename(f),
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'exptime': exptime,
                    'filter': filt,
                    'ra': ra,
                    'dec': dec
                })
            except: pass
except Exception as e:
    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

SCRIPT_EXISTS_PY=$([ "$SCRIPT_EXISTS" = "true" ] && echo "True" || echo "False")
SCRIPT_EXECUTABLE_PY=$([ "$SCRIPT_EXECUTABLE" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "script_exists": $SCRIPT_EXISTS_PY,
    "script_executable": $SCRIPT_EXECUTABLE_PY,
    "script_content_b64": "$SCRIPT_CONTENT",
    "telescope_park_state": "$PARK_STATE",
    "fits_files": $FITS_INFO
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF
echo "=== Export complete ==="