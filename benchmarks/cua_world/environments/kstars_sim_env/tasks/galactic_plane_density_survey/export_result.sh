#!/bin/bash
echo "=== Exporting galactic_plane_density_survey results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BASE_DIR="/home/ga/Images/galactic_survey"

FILES_INFO=$(python3 -c "
import os, json, glob

base = '$BASE_DIR'
files = []
# Check root for misplacements + correct subdirs
dirs_to_check = ['root'] + [f'field_0{i}' for i in range(1, 7)]

for d_name in dirs_to_check:
    d = base if d_name == 'root' else os.path.join(base, d_name)
    if not os.path.isdir(d):
        continue
        
    for pattern in [d + '/*.fits', d + '/*.fit', d + '/*.png']:
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                ftype = 'png' if f.endswith('.png') else 'fits'
                ra = ''
                dec = ''
                filt = ''
                if ftype == 'fits':
                    try:
                        from astropy.io import fits as pyfits
                        with pyfits.open(f) as hdul:
                            h = hdul[0].header
                            ra = str(h.get('OBJCTRA', h.get('RA', '')))
                            dec = str(h.get('OBJCTDEC', h.get('DEC', '')))
                            filt = str(h.get('FILTER', ''))
                    except: pass
                
                files.append({
                    'name': os.path.basename(f),
                    'dir': d_name,
                    'type': ftype,
                    'ra': ra,
                    'dec': dec,
                    'filter': filt,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

REPORT_PATH="/home/ga/Documents/galactic_survey_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

DIR_EXISTS_01=$([ -d "$BASE_DIR/field_01" ] && echo "true" || echo "false")
DIR_EXISTS_02=$([ -d "$BASE_DIR/field_02" ] && echo "true" || echo "false")
DIR_EXISTS_03=$([ -d "$BASE_DIR/field_03" ] && echo "true" || echo "false")
DIR_EXISTS_04=$([ -d "$BASE_DIR/field_04" ] && echo "true" || echo "false")
DIR_EXISTS_05=$([ -d "$BASE_DIR/field_05" ] && echo "true" || echo "false")
DIR_EXISTS_06=$([ -d "$BASE_DIR/field_06" ] && echo "true" || echo "false")

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")
DIR_EXISTS_01_PY=$([ "$DIR_EXISTS_01" = "true" ] && echo "True" || echo "False")
DIR_EXISTS_02_PY=$([ "$DIR_EXISTS_02" = "true" ] && echo "True" || echo "False")
DIR_EXISTS_03_PY=$([ "$DIR_EXISTS_03" = "true" ] && echo "True" || echo "False")
DIR_EXISTS_04_PY=$([ "$DIR_EXISTS_04" = "true" ] && echo "True" || echo "False")
DIR_EXISTS_05_PY=$([ "$DIR_EXISTS_05" = "true" ] && echo "True" || echo "False")
DIR_EXISTS_06_PY=$([ "$DIR_EXISTS_06" = "true" ] && echo "True" || echo "False")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "files_info": $FILES_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64",
    "dirs": {
        "field_01": $DIR_EXISTS_01_PY,
        "field_02": $DIR_EXISTS_02_PY,
        "field_03": $DIR_EXISTS_03_PY,
        "field_04": $DIR_EXISTS_04_PY,
        "field_05": $DIR_EXISTS_05_PY,
        "field_06": $DIR_EXISTS_06_PY
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written.")
PYEOF

echo "=== Export complete ==="