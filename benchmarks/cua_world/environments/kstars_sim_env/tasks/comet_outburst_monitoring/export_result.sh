#!/bin/bash
echo "=== Exporting comet_outburst_monitoring results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 3. Collect FITS info in comet directories
FITS_INFO=$(python3 -c "
import os, json, glob

base_dir = '/home/ga/Images/comets/29P'
files = []

for root, dirs, filenames in os.walk(base_dir):
    for filename in filenames:
        if filename.lower().endswith(('.fits', '.fit')):
            f = os.path.join(root, filename)
            try:
                stat = os.stat(f)
                
                # Default to parent directory name if header parsing fails
                parent_dir = os.path.basename(root)
                filt = parent_dir
                exptime = -1
                
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        hf = str(h.get('FILTER', '')).strip()
                        if hf: filt = hf
                        exptime = float(h.get('EXPTIME', -1))
                except:
                    pass
                    
                files.append({
                    'name': filename,
                    'dir': parent_dir,
                    'filter': filt,
                    'exptime': exptime,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 4. Check for finding chart
CHART_PATH="/home/ga/Images/comets/29P/finding_chart.png"
CHART_EXISTS="false"
CHART_SIZE=0
CHART_MTIME=0

if [ -f "$CHART_PATH" ]; then
    CHART_MTIME=$(stat -c %Y "$CHART_PATH" 2>/dev/null || echo "0")
    if [ "$CHART_MTIME" -gt "$TASK_START" ]; then
        CHART_EXISTS="true"
        CHART_SIZE=$(stat -c %s "$CHART_PATH" 2>/dev/null || echo "0")
    fi
fi

# 5. Check ICQ Report
REPORT_PATH="/home/ga/Documents/icq_report_29P.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Grab the first 100 lines and base64 encode safely
    REPORT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# 6. Build final JSON
CHART_EXISTS_PY=$([ "$CHART_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "finding_chart_exists": $CHART_EXISTS_PY,
    "finding_chart_size": $CHART_SIZE,
    "finding_chart_mtime": $CHART_MTIME,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="