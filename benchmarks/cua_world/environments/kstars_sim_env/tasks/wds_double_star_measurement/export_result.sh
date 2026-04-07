#!/bin/bash
echo "=== Exporting wds_double_star_measurement results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS info including RA/DEC from FITS headers
FITS_INFO=$(python3 -c "
import os, json, glob
try:
    from astropy.io import fits
    has_fits = True
except ImportError:
    has_fits = False

base = '/home/ga/Images/doubles'
files = []
for d in ['albireo', '61cyg', 'eta_cas']:
    path = os.path.join(base, d)
    for pattern in [path + '/*.fits', path + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                ra = ''
                dec = ''
                filt = ''
                if has_fits and stat.st_size > 0:
                    try:
                        with fits.open(f) as hdul:
                            h = hdul[0].header
                            ra = str(h.get('OBJCTRA', h.get('RA', '')))
                            dec = str(h.get('OBJCTDEC', h.get('DEC', '')))
                            filt = str(h.get('FILTER', ''))
                    except Exception:
                        pass
                files.append({
                    'name': os.path.basename(f),
                    'dir': d,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'ra': ra,
                    'dec': dec,
                    'filter': filt
                })
            except Exception:
                pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check WDS report file
REPORT_PATH="/home/ga/Documents/wds_measurements.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# Check sky capture image
SKY_CAPTURE_EXISTS="false"
if find /home/ga/Images/captures /home/ga/Images/doubles /home/ga/ -maxdepth 2 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | grep -qi "sky\|capture\|view\|field"; then
    SKY_CAPTURE_EXISTS="true"
fi

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")
SKY_CAPTURE_EXISTS_PY=$([ "$SKY_CAPTURE_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64",
    "sky_capture_exists": $SKY_CAPTURE_EXISTS_PY
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="