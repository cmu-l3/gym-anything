#!/bin/bash
echo "=== Exporting open_cluster_cmd_photometry results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 2. Collect FITS info from directories
BASE_DIR="/home/ga/Images/m44_cmd"
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$BASE_DIR'
files = []

# Check subdirectories B and V, as well as root (in case agent missed subdirs)
dirs_to_check = ['B', 'V', '']

for subdir in dirs_to_check:
    d = os.path.join(base, subdir)
    if not os.path.exists(d): continue
    
    for pattern in [os.path.join(d, '*.fits'), os.path.join(d, '*.fit')]:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                filt_val = subdir if subdir else 'unknown'
                exptime = -1
                
                # Attempt to extract FITS header data
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        hf = str(h.get('FILTER', '')).strip()
                        if hf: filt_val = hf
                        exptime = float(h.get('EXPTIME', -1))
                except:
                    pass
                
                files.append({
                    'name': os.path.basename(f),
                    'dir': subdir if subdir else 'root',
                    'filter': filt_val,
                    'exptime': exptime,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except:
                pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Check Directory Structure
DIR_B_EXISTS=$([ -d "$BASE_DIR/B" ] && echo "true" || echo "false")
DIR_V_EXISTS=$([ -d "$BASE_DIR/V" ] && echo "true" || echo "false")

# 4. Check Sky View Image
SKY_EXISTS="false"
SKY_SIZE=0
SKY_MTIME=0
SKY_PATH="$BASE_DIR/m44_sky_view.png"
if [ -f "$SKY_PATH" ]; then
    SKY_MTIME=$(stat -c %Y "$SKY_PATH" 2>/dev/null || echo "0")
    if [ "$SKY_MTIME" -gt "$TASK_START" ]; then
        SKY_EXISTS="true"
        SKY_SIZE=$(stat -c %s "$SKY_PATH" 2>/dev/null || echo "0")
    fi
fi

# 5. Check Report File
REPORT_PATH="/home/ga/Documents/m44_cmd_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
REPORT_SIZE=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DIR_B_EXISTS_PY=$([ "$DIR_B_EXISTS" = "true" ] && echo "True" || echo "False")
DIR_V_EXISTS_PY=$([ "$DIR_V_EXISTS" = "true" ] && echo "True" || echo "False")
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# 6. Write Result JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "dirs": {
        "B": $DIR_B_EXISTS_PY,
        "V": $DIR_V_EXISTS_PY
    },
    "fits_files": $FITS_INFO,
    "sky_view": {
        "exists": $SKY_EXISTS_PY,
        "mtime": $SKY_MTIME,
        "size": $SKY_SIZE
    },
    "report": {
        "exists": $REPORT_EXISTS_PY,
        "mtime": $REPORT_MTIME,
        "size": $REPORT_SIZE,
        "b64": "$REPORT_B64"
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="