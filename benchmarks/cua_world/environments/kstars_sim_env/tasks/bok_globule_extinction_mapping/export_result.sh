#!/bin/bash
echo "=== Exporting bok_globule_extinction_mapping results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Get telescope position
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null | tr -cd '0-9.' | head -c 10)
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null | sed 's/[^0-9.\-]//g' | head -c 10)
if [ -z "$FINAL_RA" ]; then FINAL_RA="-1"; fi
if [ -z "$FINAL_DEC" ]; then FINAL_DEC="-999"; fi

# 4. Gather FITS files and Focuser information from headers
FITS_INFO=$(python3 -c "
import os, json, glob

base_dir = '/home/ga/Images/dark_nebulae'
files = []

for root, dirs, filenames in os.walk(base_dir):
    for fname in filenames:
        if fname.lower().endswith(('.fits', '.fit')):
            fpath = os.path.join(root, fname)
            try:
                stat = os.stat(fpath)
                filt = ''
                focus = -1
                try:
                    from astropy.io import fits as pyfits
                    with pyfits.open(fpath) as hdul:
                        h = hdul[0].header
                        filt = str(h.get('FILTER', '')).strip()
                        focus = float(h.get('FOCUSPOS', -1))
                except: pass
                
                # Derive target and filter folder from path
                rel_path = os.path.relpath(fpath, base_dir)
                parts = rel_path.split(os.sep)
                target_dir = parts[0] if len(parts) > 1 else 'unknown'
                filter_dir = parts[1] if len(parts) > 2 else (parts[0] if len(parts)==2 else 'unknown')
                
                files.append({
                    'name': fname,
                    'path': fpath,
                    'target_dir': target_dir,
                    'filter_dir': filter_dir,
                    'header_filter': filt,
                    'header_focus': focus,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except Exception as e:
                pass

print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 5. Gather Sky View PNGs
PNG_INFO=$(python3 -c "
import os, json, glob
base_dir = '/home/ga/Images/dark_nebulae'
files = []
for pattern in [base_dir + '/**/*.png', base_dir + '/*.png']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            files.append({
                'name': os.path.basename(f),
                'path': f,
                'size': stat.st_size,
                'mtime': stat.st_mtime
            })
        except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 6. Read CSV Log
CSV_PATH="/home/ga/Documents/extinction_survey_log.csv"
CSV_EXISTS="false"
CSV_MTIME=0
CSV_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_CONTENT=$(cat "$CSV_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

CSV_EXISTS_PY=$([ "$CSV_EXISTS" = "true" ] && echo "True" || echo "False")

# 7. Write Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC",
    "fits_files": $FITS_INFO,
    "png_files": $PNG_INFO,
    "csv_exists": $CSV_EXISTS_PY,
    "csv_mtime": $CSV_MTIME,
    "csv_content_b64": "$CSV_CONTENT"
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="