#!/bin/bash
echo "=== Exporting hubble_sequence_rgb_survey results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get current telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Collect survey files info (FITS, composites, captures)
FILES_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Images/galaxy_survey'
files = []

if os.path.exists(base):
    for root, _, filenames in os.walk(base):
        for f in filenames:
            path = os.path.join(root, f)
            try:
                stat = os.stat(path)
                rel_path = os.path.relpath(path, base)
                # Parse FITS header if possible to get filter and exptime
                filt = ''
                exptime = -1
                if f.lower().endswith('.fits') or f.lower().endswith('.fit'):
                    try:
                        from astropy.io import fits as pyfits
                        with pyfits.open(path) as hdul:
                            h = hdul[0].header
                            filt = str(h.get('FILTER', '')).strip()
                            exptime = float(h.get('EXPTIME', -1))
                    except: pass
                
                files.append({
                    'name': f,
                    'path': path,
                    'rel_path': rel_path,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'filter': filt,
                    'exptime': exptime
                })
            except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 4. Check catalog file
CATALOG_PATH="/home/ga/Documents/galaxy_survey_catalog.txt"
CATALOG_EXISTS="false"
CATALOG_MTIME=0
CATALOG_B64=""

if [ -f "$CATALOG_PATH" ]; then
    CATALOG_EXISTS="true"
    CATALOG_MTIME=$(stat -c %Y "$CATALOG_PATH" 2>/dev/null || echo "0")
    CATALOG_B64=$(head -n 50 "$CATALOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

CATALOG_EXISTS_PY=$([ "$CATALOG_EXISTS" = "true" ] && echo "True" || echo "False")

# 5. Dump to JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "files_info": $FILES_INFO,
    "catalog_exists": $CATALOG_EXISTS_PY,
    "catalog_mtime": $CATALOG_MTIME,
    "catalog_b64": "$CATALOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="