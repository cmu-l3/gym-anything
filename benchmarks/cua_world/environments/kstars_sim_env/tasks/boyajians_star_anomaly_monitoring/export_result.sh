#!/bin/bash
echo "=== Exporting boyajians_star_anomaly_monitoring results ==="

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

base = '/home/ga/Images/kic8462852'
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
                        if hf:
                            filt = hf
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                files.append({'name': os.path.basename(f), 'dir': subdir,
                              'filter': filt, 'exptime': exptime,
                              'size': stat.st_size, 'mtime': stat.st_mtime})
            except: pass
            
# Also catch stray frames in the base dir or anywhere else
for pattern in [base + '/*.fits', base + '/*.fit']:
    for f in glob.glob(pattern):
        try:
            stat = os.stat(f)
            filt = 'unknown'
            exptime = -1
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    filt = str(h.get('FILTER', '')).strip()
                    exptime = float(h.get('EXPTIME', -1))
            except: pass
            files.append({'name': os.path.basename(f), 'dir': 'base',
                          'filter': filt, 'exptime': exptime,
                          'size': stat.st_size, 'mtime': stat.st_mtime})
        except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check finding chart
CHART_EXISTS="false"
CHART_MTIME=0
if [ -f "/home/ga/Images/kic8462852/finding_chart.png" ]; then
    CHART_MTIME=$(stat -c %Y "/home/ga/Images/kic8462852/finding_chart.png" 2>/dev/null || echo "0")
    if [ "$CHART_MTIME" -gt "$TASK_START" ]; then
        CHART_EXISTS="true"
    fi
fi

# Check summary report
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "/home/ga/Documents/tabbys_star_report.txt" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "/home/ga/Documents/tabbys_star_report.txt" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "/home/ga/Documents/tabbys_star_report.txt" | base64 -w 0 2>/dev/null || echo "")
fi

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
    "finding_chart_mtime": $CHART_MTIME,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="