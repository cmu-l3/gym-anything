#!/bin/bash
echo "=== Exporting ccd_photometric_linearity_calibration results ==="

source /workspace/scripts/task_utils.sh

# ── 1. Take final screenshot ──────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 2. Get current telescope position ─────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# ── 3. Collect FITS files information ─────────────────────────────────
LINEARITY_DIR="/home/ga/Images/engineering/linearity"
FITS_FILES_INFO=$(python3 -c "
import os, json, glob

base_dir = '$LINEARITY_DIR'
files = []
if os.path.exists(base_dir):
    for root_d, dirs, file_names in os.walk(base_dir):
        for name in file_names:
            if name.lower().endswith('.fits') or name.lower().endswith('.fit'):
                fpath = os.path.join(root_d, name)
                try:
                    stat = os.stat(fpath)
                    exptime = -1.0
                    filt = ''
                    try:
                        from astropy.io import fits as pyfits
                        with pyfits.open(fpath) as hdul:
                            exptime = float(hdul[0].header.get('EXPTIME', -1.0))
                            filt = str(hdul[0].header.get('FILTER', '')).strip()
                    except Exception as e:
                        pass
                    subdir = os.path.basename(root_d)
                    files.append({
                        'name': name,
                        'dir': subdir,
                        'filter': filt,
                        'exptime': exptime,
                        'size': stat.st_size,
                        'mtime': stat.st_mtime
                    })
                except Exception:
                    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# ── 4. Check for sky capture image ────────────────────────────────────
REF_IMAGE_PATH="/home/ga/Images/engineering/m67_reference.png"
REF_IMAGE_EXISTS="false"
REF_IMAGE_MTIME=0

if [ -f "$REF_IMAGE_PATH" ]; then
    REF_IMAGE_EXISTS="true"
    REF_IMAGE_MTIME=$(stat -c %Y "$REF_IMAGE_PATH" 2>/dev/null || echo "0")
fi

# ── 5. Check report file ──────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/linearity_test_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# ── 6. Get task start time ────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 7. Write result JSON ──────────────────────────────────────────────
REF_IMAGE_EXISTS_PY=$([ "$REF_IMAGE_EXISTS" = "true" ] && echo "True" || echo "False")
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json, os

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_FILES_INFO,
    "ref_image_exists": $REF_IMAGE_EXISTS_PY,
    "ref_image_mtime": $REF_IMAGE_MTIME,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="
cat /tmp/task_result.json