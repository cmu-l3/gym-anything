#!/bin/bash
echo "=== Exporting globular_cluster_hdr_profiling results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# Collect FITS files info
FITS_INFO=$(python3 -c "
import os, json, glob

base_dir = '/home/ga/Images/M15_HDR'
subdirs = ['1s', '5s', '15s', '60s']
files = []

for subdir in subdirs:
    target_path = os.path.join(base_dir, subdir)
    for ext in ['*.fits', '*.fit']:
        pattern = os.path.join(target_path, ext)
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                exptime = -1
                filt = ''
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        exptime = float(h.get('EXPTIME', -1))
                        filt = str(h.get('FILTER', ''))
                except:
                    pass
                files.append({
                    'name': os.path.basename(f),
                    'dir': subdir,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'exptime': exptime,
                    'filter': filt
                })
            except Exception:
                pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check false-color sky view
SKY_EXISTS="false"
SKY_PATH="/home/ga/Images/M15_HDR/sky_view_cool.png"
if [ -f "$SKY_PATH" ]; then
    SKY_MTIME=$(stat -c %Y "$SKY_PATH" 2>/dev/null || echo "0")
    if [ "$SKY_MTIME" -gt "$TASK_START" ]; then
        SKY_EXISTS="true"
    fi
fi

# Check summary log
SUMMARY_EXISTS="false"
SUMMARY_PATH="/home/ga/Documents/hdr_summary.txt"
SUMMARY_B64=""
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    if [ "$SUMMARY_MTIME" -gt "$TASK_START" ]; then
        SUMMARY_EXISTS="true"
        SUMMARY_B64=$(head -n 50 "$SUMMARY_PATH" | base64 -w 0 2>/dev/null || echo "")
    fi
fi

# Convert to Python booleans
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")
SUMMARY_EXISTS_PY=$([ "$SUMMARY_EXISTS" = "true" ] && echo "True" || echo "False")

# Export to JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "sky_capture_exists": $SKY_EXISTS_PY,
    "summary_exists": $SUMMARY_EXISTS_PY,
    "summary_b64": "$SUMMARY_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="