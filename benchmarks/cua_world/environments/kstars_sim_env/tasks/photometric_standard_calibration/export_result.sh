#!/bin/bash
echo "=== Exporting photometric_standard_calibration results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SA98_BASE="/home/ga/Images/photcal/sa98"

# Collect FITS info per filter subdirectory (B/, V/, R/)
# Also scan root sa98/ as fallback (in case agent did not use subdirs)
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$SA98_BASE'
files = []
for subdir in ['B', 'V', 'R']:
    d = os.path.join(base, subdir)
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                filt = subdir
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        hf = str(h.get('FILTER', '')).strip()
                        if hf: filt = hf
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({'name': os.path.basename(f), 'dir': subdir,
                              'filter': filt, 'exptime': exptime,
                              'size': stat.st_size, 'mtime': stat.st_mtime})
            except: pass
# Also scan root directory (fallback, uses FITS FILTER header to classify)
for pattern in [base + '/*.fits', base + '/*.fit']:
    for f in glob.glob(pattern):
        try:
            stat = os.stat(f)
            filt = ''
            exptime = -1
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    filt = str(h.get('FILTER', '')).strip()
                    exptime = float(h.get('EXPTIME', -1))
            except: pass
            files.append({'name': os.path.basename(f), 'dir': 'root',
                          'filter': filt, 'exptime': exptime,
                          'size': stat.st_size, 'mtime': stat.st_mtime})
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

DIR_B=$([ -d "$SA98_BASE/B" ] && echo "true" || echo "false")
DIR_V=$([ -d "$SA98_BASE/V" ] && echo "true" || echo "false")
DIR_R=$([ -d "$SA98_BASE/R" ] && echo "true" || echo "false")

SKY_EXISTS="false"
if [ -f "$SA98_BASE/sky_view.png" ]; then
    SKY_MTIME=$(stat -c %Y "$SA98_BASE/sky_view.png" 2>/dev/null || echo "0")
    [ "$SKY_MTIME" -gt "$TASK_START" ] && SKY_EXISTS="true"
fi

CATALOG_PATH="$SA98_BASE/calibration_catalog.txt"
CATALOG_EXISTS="false"
CATALOG_MTIME=0
CATALOG_B64=""
if [ -f "$CATALOG_PATH" ]; then
    CATALOG_EXISTS="true"
    CATALOG_MTIME=$(stat -c %Y "$CATALOG_PATH" 2>/dev/null || echo "0")
    CATALOG_B64=$(head -n 30 "$CATALOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DIR_B_PY=$([ "$DIR_B" = "true" ] && echo "True" || echo "False")
DIR_V_PY=$([ "$DIR_V" = "true" ] && echo "True" || echo "False")
DIR_R_PY=$([ "$DIR_R" = "true" ] && echo "True" || echo "False")
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
CATALOG_EXISTS_PY=$([ "$CATALOG_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "dirs": {"B": $DIR_B_PY, "V": $DIR_V_PY, "R": $DIR_R_PY},
    "sky_capture_exists": $SKY_EXISTS_PY,
    "catalog_exists": $CATALOG_EXISTS_PY,
    "catalog_mtime": $CATALOG_MTIME,
    "catalog_b64": "$CATALOG_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="
