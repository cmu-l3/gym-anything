#!/bin/bash
echo "=== Exporting ccd_gain_readnoise_characterization results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect info from directories
FITS_INFO=$(python3 -c "
import os, json, glob

cal_root = '/home/ga/Calibration/ccd_characterization'
dirs = {
    'flats_1s': os.path.join(cal_root, 'flats_1s'),
    'flats_5s': os.path.join(cal_root, 'flats_5s'),
    'flats_15s': os.path.join(cal_root, 'flats_15s'),
    'bias': os.path.join(cal_root, 'bias')
}

files = []
for category, dirpath in dirs.items():
    for pattern in [dirpath + '/*.fits', dirpath + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                frame_type = ''
                exptime = -1.0
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        frame_type = str(h.get('IMAGETYP', h.get('FRAME', '')))
                        exptime = float(h.get('EXPTIME', -1.0))
                except: pass
                files.append({
                    'name': os.path.basename(f),
                    'category': category,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'frame_type': frame_type,
                    'exptime': exptime
                })
            except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check report file
REPORT_PATH="/home/ga/Documents/ccd_characterization_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DIR_F1=$([ -d "/home/ga/Calibration/ccd_characterization/flats_1s" ] && echo "true" || echo "false")
DIR_F5=$([ -d "/home/ga/Calibration/ccd_characterization/flats_5s" ] && echo "true" || echo "false")
DIR_F15=$([ -d "/home/ga/Calibration/ccd_characterization/flats_15s" ] && echo "true" || echo "false")
DIR_BIAS=$([ -d "/home/ga/Calibration/ccd_characterization/bias" ] && echo "true" || echo "false")

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")
DIR_F1_PY=$([ "$DIR_F1" = "true" ] && echo "True" || echo "False")
DIR_F5_PY=$([ "$DIR_F5" = "true" ] && echo "True" || echo "False")
DIR_F15_PY=$([ "$DIR_F15" = "true" ] && echo "True" || echo "False")
DIR_BIAS_PY=$([ "$DIR_BIAS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64",
    "dirs": {
        "flats_1s": $DIR_F1_PY,
        "flats_5s": $DIR_F5_PY,
        "flats_15s": $DIR_F15_PY,
        "bias": $DIR_BIAS_PY
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="