#!/bin/bash
echo "=== Exporting automated_galaxy_cluster_atlas_generation results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Get final telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 3. Check for the automation script
SCRIPT_EXISTS="false"
SCRIPT_MTIME=0
if [ -f "/home/ga/build_atlas.sh" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "/home/ga/build_atlas.sh" 2>/dev/null || echo "0")
elif [ -f "/home/ga/build_atlas.py" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "/home/ga/build_atlas.py" 2>/dev/null || echo "0")
fi

# 4. Gather generated output images and compute MD5 hashes
IMAGES_INFO=$(python3 -c "
import os, json, glob, hashlib
d = '/home/ga/Images/cluster_atlas'
files = []
if os.path.exists(d):
    for pattern in [d + '/*_survey.png', d + '/*_survey.PNG']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                with open(f, 'rb') as fp:
                    md5 = hashlib.md5(fp.read()).hexdigest()
                files.append({
                    'name': os.path.basename(f),
                    'size': stat.st_size,
                    'mtime': stat.st_mtime,
                    'md5': md5
                })
            except Exception as e: 
                pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

DIR_EXISTS=$([ -d "/home/ga/Images/cluster_atlas" ] && echo "True" || echo "False")
SCRIPT_EXISTS_PY=$([ "$SCRIPT_EXISTS" = "true" ] && echo "True" || echo "False")

# 5. Export JSON result
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "script_exists": $SCRIPT_EXISTS_PY,
    "script_mtime": $SCRIPT_MTIME,
    "dir_exists": $DIR_EXISTS,
    "images": $IMAGES_INFO
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json.")
PYEOF

echo "=== Export complete ==="