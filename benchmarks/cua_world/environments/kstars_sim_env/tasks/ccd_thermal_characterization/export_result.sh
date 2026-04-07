#!/bin/bash
echo "=== Exporting ccd_thermal_characterization results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS info
FITS_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Calibration/thermal_profile'
files = []
for root, dirs, filenames in os.walk(base):
    for filename in filenames:
        if filename.lower().endswith('.fits') or filename.lower().endswith('.fit'):
            filepath = os.path.join(root, filename)
            rel_dir = os.path.relpath(root, base)
            try:
                stat = os.stat(filepath)
                frame_type = ''
                exptime = -1
                ccd_temp = -999.0
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(filepath) as hdul:
                        h = hdul[0].header
                        frame_type = str(h.get('IMAGETYP', h.get('FRAME', '')))
                        exptime = float(h.get('EXPTIME', -1))
                        ccd_temp = float(h.get('CCD-TEMP', -999.0))
                except: pass
                files.append({
                    'name': filename,
                    'dir': rel_dir,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'frame_type': frame_type,
                    'exptime': exptime,
                    'ccd_temp': ccd_temp
                })
            except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

REPORT_PATH="/home/ga/Documents/thermal_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

DIR_0C=$([ -d "/home/ga/Calibration/thermal_profile/0C" ] && echo "true" || echo "false")
DIR_M10C=$([ -d "/home/ga/Calibration/thermal_profile/minus10C" ] && echo "true" || echo "false")
DIR_M20C=$([ -d "/home/ga/Calibration/thermal_profile/minus20C" ] && echo "true" || echo "false")

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")
DIR_0C_PY=$([ "$DIR_0C" = "true" ] && echo "True" || echo "False")
DIR_M10C_PY=$([ "$DIR_M10C" = "true" ] && echo "True" || echo "False")
DIR_M20C_PY=$([ "$DIR_M20C" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "dirs": {
        "0C": $DIR_0C_PY,
        "minus10C": $DIR_M10C_PY,
        "minus20C": $DIR_M20C_PY
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="