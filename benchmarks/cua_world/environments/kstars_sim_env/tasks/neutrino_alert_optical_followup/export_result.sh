#!/bin/bash
echo "=== Exporting neutrino_alert_optical_followup results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS info from the target directory structure
FOLLOWUP_DIR="/home/ga/Images/neutrino_followup"
FITS_INFO=$(python3 -c "
import os, json, glob

base = '$FOLLOWUP_DIR'
files = []
if os.path.exists(base):
    for root, dirs, filenames in os.walk(base):
        for fname in filenames:
            if fname.lower().endswith(('.fits', '.fit')):
                fpath = os.path.join(root, fname)
                try:
                    stat = os.stat(fpath)
                    filt = ''
                    exptime = -1
                    try:
                        from astropy.io import fits as pyfits
                        with pyfits.open(fpath) as hdul:
                            h = hdul[0].header
                            filt = str(h.get('FILTER', '')).strip()
                            exptime = float(h.get('EXPTIME', -1))
                    except: pass
                    
                    # Store candidate directory name as the target reference
                    cand_dir = os.path.basename(root)
                    
                    files.append({
                        'name': fname,
                        'path': fpath,
                        'candidate': cand_dir,
                        'filter': filt,
                        'exptime': exptime,
                        'size': stat.st_size,
                        'mtime': stat.st_mtime
                    })
                except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Scan for DSS reference PNGs
PNG_INFO=$(python3 -c "
import os, json, glob

base = '$FOLLOWUP_DIR'
files = []
if os.path.exists(base):
    for root, dirs, filenames in os.walk(base):
        for fname in filenames:
            if fname == 'dss_reference.png':
                fpath = os.path.join(root, fname)
                try:
                    stat = os.stat(fpath)
                    cand_dir = os.path.basename(root)
                    files.append({
                        'name': fname,
                        'path': fpath,
                        'candidate': cand_dir,
                        'size': stat.st_size,
                        'mtime': stat.st_mtime
                    })
                except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check draft report
REPORT_PATH="/home/ga/Documents/gcn_circular_draft.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 100 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "png_files": $PNG_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="