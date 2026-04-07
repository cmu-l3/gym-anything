#!/bin/bash
echo "=== Exporting arp_interacting_galaxies_survey results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS and PNG info across the survey base directory
python3 -c "
import os, json, glob

base = '/home/ga/Images/arp_survey'
fits_list = []
png_list = []

for root, dirs, files in os.walk(base):
    for name in files:
        filepath = os.path.join(root, name)
        try:
            stat = os.stat(filepath)
            rel_dir = os.path.basename(root)
            
            if name.lower().endswith('.fits') or name.lower().endswith('.fit'):
                filt = ''
                exptime = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(filepath) as hdul:
                        h = hdul[0].header
                        hf = str(h.get('FILTER', '')).strip()
                        if hf: filt = hf
                        exptime = float(h.get('EXPTIME', -1))
                except: pass
                fits_list.append({
                    'name': name, 'dir': rel_dir, 'filter': filt, 'exptime': exptime, 
                    'size': stat.st_size, 'mtime': stat.st_mtime
                })
            elif name.lower().endswith('.png'):
                png_list.append({
                    'name': name, 'dir': rel_dir, 'size': stat.st_size, 'mtime': stat.st_mtime
                })
        except Exception as e:
            pass

with open('/tmp/media_info.json', 'w') as f:
    json.dump({'fits': fits_list, 'pngs': png_list}, f)
" 2>/dev/null || echo '{"fits": [], "pngs": []}' > /tmp/media_info.json

# Check if the JSON survey log exists and extract it
LOG_PATH="/home/ga/Documents/arp_survey_log.json"
LOG_EXISTS="false"
LOG_CONTENT_B64=""
if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_CONTENT_B64=$(cat "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")

# Assemble final results securely via Python to avoid shell escape issues
python3 - << PYEOF
import json
import os
import time

try:
    with open('/tmp/media_info.json', 'r') as f:
        media_info = json.load(f)
except:
    media_info = {"fits": [], "pngs": []}

result = {
    "task_start": $TASK_START,
    "timestamp": int(time.time()),
    "media_info": media_info,
    "log_exists": $LOG_EXISTS_PY,
    "log_content_b64": "$LOG_CONTENT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="