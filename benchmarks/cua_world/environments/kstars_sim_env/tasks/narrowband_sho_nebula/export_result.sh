#!/bin/bash
echo "=== Exporting narrowband_sho_nebula results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# Collect FITS info per filter sub-directory
FITS_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Images/ngc7000/narrowband'
files = []
for subdir in ['Ha', 'OIII', 'SII']:
    d = os.path.join(base, subdir)
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                # Try reading FITS header
                filt = subdir  # default to directory name
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        hf = str(h.get('FILTER', '')).strip()
                        if hf:
                            filt = hf
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({'name': os.path.basename(f), 'dir': subdir,
                              'filter': filt, 'exptime': exptime,
                              'size': stat.st_size, 'mtime': stat.st_mtime})
            except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check composite image
COMPOSITE_EXISTS="false"
COMPOSITE_MTIME=0
if [ -f "/home/ga/Images/ngc7000/composite_sho.png" ]; then
    COMPOSITE_MTIME=$(stat -c %Y "/home/ga/Images/ngc7000/composite_sho.png" 2>/dev/null || echo "0")
    if [ "$COMPOSITE_MTIME" -gt "$TASK_START" ]; then
        COMPOSITE_EXISTS="true"
    fi
fi

# Check sky capture
SKY_EXISTS="false"
if [ -f "/home/ga/Images/ngc7000/sky_view.png" ]; then
    SKY_MTIME=$(stat -c %Y "/home/ga/Images/ngc7000/sky_view.png" 2>/dev/null || echo "0")
    [ "$SKY_MTIME" -gt "$TASK_START" ] && SKY_EXISTS="true"
fi

# Get composite file size
COMPOSITE_SIZE=0
if [ "$COMPOSITE_EXISTS" = "true" ]; then
    COMPOSITE_SIZE=$(stat -c %s "/home/ga/Images/ngc7000/composite_sho.png" 2>/dev/null || echo "0")
fi

COMPOSITE_EXISTS_PY=$([ "$COMPOSITE_EXISTS" = "true" ] && echo "True" || echo "False")
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "composite_exists": $COMPOSITE_EXISTS_PY,
    "composite_mtime": $COMPOSITE_MTIME,
    "composite_size": $COMPOSITE_SIZE,
    "sky_capture_exists": $SKY_EXISTS_PY
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="
