#!/bin/bash
echo "=== Exporting optical_pulsar_subframing results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Get telescope final coordinates
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 2. Extract FITS details using Python
UPLOAD_DIR="/home/ga/Images/pulsar_data/crab"
FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    from astropy.io import fits as pyfits
except ImportError:
    pyfits = None

for pattern in ['$UPLOAD_DIR/*.fits', '$UPLOAD_DIR/*.fit']:
    for f in glob.glob(pattern):
        try:
            stat = os.stat(f)
            
            naxis1 = -1
            naxis2 = -1
            xbin = -1
            ybin = -1
            exptime = -1.0
            filt = ''
            
            if pyfits is not None and stat.st_size > 1024:
                try:
                    with pyfits.open(f, ignore_missing_end=True) as hdul:
                        h = hdul[0].header
                        naxis1 = int(h.get('NAXIS1', -1))
                        naxis2 = int(h.get('NAXIS2', -1))
                        xbin = int(h.get('XBINNING', 1))
                        ybin = int(h.get('YBINNING', 1))
                        exptime = float(h.get('EXPTIME', -1.0))
                        filt = str(h.get('FILTER', h.get('FILTER1', ''))).strip()
                except Exception as e:
                    pass
            
            files.append({
                'name': os.path.basename(f),
                'size': stat.st_size,
                'mtime': stat.st_mtime,
                'naxis1': naxis1,
                'naxis2': naxis2,
                'xbin': xbin,
                'ybin': ybin,
                'exptime': exptime,
                'filter': filt
            })
        except Exception:
            pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Check Context Image
CONTEXT_IMAGE_PATH="/home/ga/Images/pulsar_data/crab_context.png"
CONTEXT_EXISTS="false"
CONTEXT_MTIME=0
if [ -f "$CONTEXT_IMAGE_PATH" ]; then
    CONTEXT_MTIME=$(stat -c %Y "$CONTEXT_IMAGE_PATH" 2>/dev/null || echo "0")
    if [ "$CONTEXT_MTIME" -gt "$TASK_START" ]; then
        CONTEXT_EXISTS="true"
    fi
fi

CONTEXT_EXISTS_PY=$([ "$CONTEXT_EXISTS" = "true" ] && echo "True" || echo "False")

# 4. Write to JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "context_exists": $CONTEXT_EXISTS_PY,
    "context_mtime": $CONTEXT_MTIME
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="