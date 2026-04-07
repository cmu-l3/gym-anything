#!/bin/bash
echo "=== Exporting calibration_library_production results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect info from all calibration directories
FITS_INFO=$(python3 -c "
import os, json, glob

cal_root = '/home/ga/Calibration'
dirs = {
    'bias': os.path.join(cal_root, 'bias'),
    'dark_300s': os.path.join(cal_root, 'darks', '300s'),
    'dark_600s': os.path.join(cal_root, 'darks', '600s'),
    'flat_V': os.path.join(cal_root, 'flats', 'V'),
    'flat_R': os.path.join(cal_root, 'flats', 'R'),
    'flat_B': os.path.join(cal_root, 'flats', 'B')
}

files = []
for category, dirpath in dirs.items():
    for pattern in [dirpath + '/*.fits', dirpath + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                frame_type = ''
                exptime = -1
                filt = ''
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        frame_type = str(h.get('IMAGETYP', h.get('FRAME', '')))
                        exptime = float(h.get('EXPTIME', -1))
                        filt = str(h.get('FILTER', ''))
                except: pass
                files.append({
                    'name': os.path.basename(f),
                    'category': category,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'frame_type': frame_type,
                    'exptime': exptime,
                    'filter': filt
                })
            except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check summary file
SUMMARY_PATH="/home/ga/Calibration/calibration_summary.txt"
SUMMARY_EXISTS="false"
SUMMARY_MTIME=0
SUMMARY_B64=""
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    SUMMARY_B64=$(head -n 30 "$SUMMARY_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# Check directory structure
DIR_BIAS=$([ -d "/home/ga/Calibration/bias" ] && echo "true" || echo "false")
DIR_DARK300=$([ -d "/home/ga/Calibration/darks/300s" ] && echo "true" || echo "false")
DIR_DARK600=$([ -d "/home/ga/Calibration/darks/600s" ] && echo "true" || echo "false")
DIR_FLAT_V=$([ -d "/home/ga/Calibration/flats/V" ] && echo "true" || echo "false")
DIR_FLAT_R=$([ -d "/home/ga/Calibration/flats/R" ] && echo "true" || echo "false")
DIR_FLAT_B=$([ -d "/home/ga/Calibration/flats/B" ] && echo "true" || echo "false")

SUMMARY_EXISTS_PY=$([ "$SUMMARY_EXISTS" = "true" ] && echo "True" || echo "False")
DIR_BIAS_PY=$([ "$DIR_BIAS" = "true" ] && echo "True" || echo "False")
DIR_DARK300_PY=$([ "$DIR_DARK300" = "true" ] && echo "True" || echo "False")
DIR_DARK600_PY=$([ "$DIR_DARK600" = "true" ] && echo "True" || echo "False")
DIR_FLAT_V_PY=$([ "$DIR_FLAT_V" = "true" ] && echo "True" || echo "False")
DIR_FLAT_R_PY=$([ "$DIR_FLAT_R" = "true" ] && echo "True" || echo "False")
DIR_FLAT_B_PY=$([ "$DIR_FLAT_B" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "summary_exists": $SUMMARY_EXISTS_PY,
    "summary_mtime": $SUMMARY_MTIME,
    "summary_b64": "$SUMMARY_B64",
    "dirs": {
        "bias": $DIR_BIAS_PY,
        "dark_300s": $DIR_DARK300_PY,
        "dark_600s": $DIR_DARK600_PY,
        "flat_V": $DIR_FLAT_V_PY,
        "flat_R": $DIR_FLAT_R_PY,
        "flat_B": $DIR_FLAT_B_PY
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="
