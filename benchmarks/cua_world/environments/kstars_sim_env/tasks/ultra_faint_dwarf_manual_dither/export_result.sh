#!/bin/bash
echo "=== Exporting ultra_faint_dwarf_manual_dither results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect info on all FITS files recursively from leo1 dir
# Parses FITS metadata directly to verify physical coordinate offsets
FITS_INFO=$(python3 -c "
import os, json, glob

base_dir = '/home/ga/Images/leo1'
files = []

for pos_dir in ['center', 'north', 'south', 'east', 'west']:
    d = os.path.join(base_dir, pos_dir)
    for pattern in [d + '/*.fits', d + '/*.fit']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                filt = ''
                exptime = -1
                objctra = ''
                objctdec = ''
                
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(f) as hdul:
                        h = hdul[0].header
                        filt = str(h.get('FILTER', ''))
                        exptime = float(h.get('EXPTIME', -1))
                        objctra = str(h.get('OBJCTRA', ''))
                        objctdec = str(h.get('OBJCTDEC', ''))
                except: pass
                
                files.append({
                    'name': os.path.basename(f),
                    'dir': pos_dir,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'filter': filt,
                    'exptime': exptime,
                    'objctra': objctra,
                    'objctdec': objctdec
                })
            except Exception as e:
                pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check for the agent's summary log
LOG_PATH="/home/ga/Documents/dither_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0

if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
fi

LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

# Export strictly to /tmp/task_result.json
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="