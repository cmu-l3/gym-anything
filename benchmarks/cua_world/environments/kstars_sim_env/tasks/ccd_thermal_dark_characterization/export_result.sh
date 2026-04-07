#!/bin/bash
echo "=== Exporting ccd_thermal_dark_characterization results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS file metadata directly from headers using Astropy
FITS_INFO=$(python3 -c "
import os, json, glob

base_dir = '/home/ga/Calibration/thermal'
files = []

for root, _, filenames in os.walk(base_dir):
    for filename in filenames:
        if filename.lower().endswith(('.fits', '.fit')):
            fpath = os.path.join(root, filename)
            try:
                stat = os.stat(fpath)
                mtime = stat.st_mtime
                size = stat.st_size
                
                # Default empty header info
                img_typ = ''
                exp_time = -1.0
                ccd_temp = -999.0
                
                if size > 0:
                    try:
                        from astropy.io import fits as pyfits
                        with pyfits.open(fpath) as hdul:
                            hdr = hdul[0].header
                            img_typ = str(hdr.get('IMAGETYP', hdr.get('FRAME', ''))).strip()
                            exp_time = float(hdr.get('EXPTIME', -1))
                            ccd_temp = float(hdr.get('CCD-TEMP', -999.0))
                    except Exception as e:
                        pass
                        
                files.append({
                    'name': filename,
                    'path': fpath,
                    'dir': os.path.basename(root),
                    'size': size,
                    'mtime': mtime,
                    'imagetyp': img_typ,
                    'exptime': exp_time,
                    'ccd_temp': ccd_temp
                })
            except:
                pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check directories
DIR_0C=$([ -d "/home/ga/Calibration/thermal/0C" ] && echo "true" || echo "false")
DIR_MINUS10=$([ -d "/home/ga/Calibration/thermal/minus10C" ] && echo "true" || echo "false")
DIR_MINUS20=$([ -d "/home/ga/Calibration/thermal/minus20C" ] && echo "true" || echo "false")

# Check report
REPORT_PATH="/home/ga/Documents/thermal_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DIR_0C_PY=$([ "$DIR_0C" = "true" ] && echo "True" || echo "False")
DIR_MINUS10_PY=$([ "$DIR_MINUS10" = "true" ] && echo "True" || echo "False")
DIR_MINUS20_PY=$([ "$DIR_MINUS20" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# Write JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "dirs": {
        "0C": $DIR_0C_PY,
        "minus10C": $DIR_MINUS10_PY,
        "minus20C": $DIR_MINUS20_PY
    },
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="