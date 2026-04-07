#!/bin/bash
echo "=== Exporting ccd_instrument_commissioning results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 2. Get current telescope position ─────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# ── 3. Parse FITS files using Python ──────────────────────────────────
BASE_DIR="/home/ga/Images/commissioning"
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$BASE_DIR'
files = []

for subdir in ['filters', 'binning', 'roi']:
    d = os.path.join(base, subdir)
    if not os.path.isdir(d):
        continue
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                filt = ''
                xbin = -1
                ybin = -1
                naxis1 = -1
                naxis2 = -1
                
                # Check if it's a 0-byte stub
                if stat.st_size > 0:
                    try:
                        from astropy.io import fits as pyfits
                        with pyfits.open(f) as hdul:
                            h = hdul[0].header
                            hf = str(h.get('FILTER', h.get('FILTER2', ''))).strip()
                            if hf: filt = hf
                            xbin = int(h.get('XBINNING', -1))
                            ybin = int(h.get('YBINNING', -1))
                            naxis1 = int(h.get('NAXIS1', -1))
                            naxis2 = int(h.get('NAXIS2', -1))
                    except Exception as e:
                        pass
                
                files.append({
                    'name': os.path.basename(f),
                    'dir': subdir,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'filter': filt,
                    'xbin': xbin,
                    'ybin': ybin,
                    'naxis1': naxis1,
                    'naxis2': naxis2
                })
            except Exception as e:
                pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 4. Check report file ──────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/commissioning_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# ── 5. Get task start time ────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 6. Write result JSON ──────────────────────────────────────────────
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json, os

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="