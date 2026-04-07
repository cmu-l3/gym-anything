#!/bin/bash
echo "=== Exporting snr_multiwavelength_correlation results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract final telescope state
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Collect files and calculate md5 hashes for PNGs to prevent gaming
FITS_AND_PNG_INFO=$(python3 -c "
import os, json, glob, hashlib

base = '/home/ga/Images/SNR'
files = []

if os.path.exists(base):
    for root, dirs, filenames in os.walk(base):
        for fname in filenames:
            fpath = os.path.join(root, fname)
            try:
                stat = os.stat(fpath)
                rel_path = os.path.relpath(fpath, base)
                parts = rel_path.split(os.sep)
                target = parts[0] if len(parts) > 0 else 'unknown'
                subdir = parts[1] if len(parts) > 1 else 'unknown'
                
                info = {
                    'name': fname,
                    'path': fpath,
                    'target': target,
                    'subdir': subdir,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'md5': '',
                    'filter': ''
                }
                
                if fname.lower().endswith('.png'):
                    with open(fpath, 'rb') as f:
                        info['md5'] = hashlib.md5(f.read()).hexdigest()
                        
                elif fname.lower().endswith('.fits') or fname.lower().endswith('.fit'):
                    try:
                        from astropy.io import fits as pyfits
                        with pyfits.open(fpath) as hdul:
                            hf = str(hdul[0].header.get('FILTER', '')).strip()
                            if hf:
                                info['filter'] = hf
                    except: 
                        pass
                        
                files.append(info)
            except Exception as e:
                pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 4. Check report
REPORT_PATH="/home/ga/Documents/snr_correlation_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi
REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# 5. Write result JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "files_info": $FITS_AND_PNG_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="