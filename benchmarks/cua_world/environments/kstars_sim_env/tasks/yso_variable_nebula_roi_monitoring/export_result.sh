#!/bin/bash
echo "=== Exporting yso_variable_nebula_roi_monitoring results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Get CCD final state (to check if they restored full frame)
FINAL_CCD_W=$(indi_getprop -1 "CCD Simulator.CCD_FRAME.WIDTH" 2>/dev/null | tr -cd '0-9' || echo "-1")
FINAL_CCD_H=$(indi_getprop -1 "CCD Simulator.CCD_FRAME.HEIGHT" 2>/dev/null | tr -cd '0-9' || echo "-1")
FINAL_CCD_X=$(indi_getprop -1 "CCD Simulator.CCD_FRAME.X" 2>/dev/null | tr -cd '0-9' || echo "-1")
FINAL_CCD_Y=$(indi_getprop -1 "CCD Simulator.CCD_FRAME.Y" 2>/dev/null | tr -cd '0-9' || echo "-1")

# 2. Collect FITS information
FITS_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Images/yso'
files = []
for pattern in [base + '/**/*.fits', base + '/**/*.fit']:
    for f in glob.glob(pattern, recursive=True):
        try:
            stat = os.stat(f)
            hf_ra, hf_dec = '', ''
            hf_w, hf_h = 0, 0
            hf_x, hf_y = -1, -1
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    hf_ra = str(h.get('OBJCTRA', h.get('RA', '')))
                    hf_dec = str(h.get('OBJCTDEC', h.get('DEC', '')))
                    hf_w = h.get('NAXIS1', 0)
                    hf_h = h.get('NAXIS2', 0)
                    # Check standard FITS keywords for ROI offsets
                    hf_x = h.get('XOFFSET', h.get('XORGSUBF', 0))
                    hf_y = h.get('YOFFSET', h.get('YORGSUBF', 0))
            except: pass
            
            # Identify which target folder this is in
            parent_dir = os.path.basename(os.path.dirname(f))
            
            files.append({
                'name': os.path.basename(f), 
                'dir': parent_dir,
                'path': f,
                'size': stat.st_size, 
                'mtime': stat.st_mtime,
                'ra': hf_ra,
                'dec': hf_dec,
                'width': hf_w,
                'height': hf_h,
                'x_offset': hf_x,
                'y_offset': hf_y
            })
        except Exception as e:
            pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Check for sky context image
CONTEXT_EXISTS="false"
CONTEXT_PATH="/home/ga/Images/yso/mcneils/sky_context.png"
if [ -f "$CONTEXT_PATH" ]; then
    CONTEXT_MTIME=$(stat -c %Y "$CONTEXT_PATH" 2>/dev/null || echo "0")
    if [ "$CONTEXT_MTIME" -gt "$TASK_START" ]; then
        CONTEXT_EXISTS="true"
    fi
fi

CONTEXT_EXISTS_PY=$([ "$CONTEXT_EXISTS" = "true" ] && echo "True" || echo "False")

# 4. Write to JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "ccd_final_state": {
        "width": "$FINAL_CCD_W",
        "height": "$FINAL_CCD_H",
        "x": "$FINAL_CCD_X",
        "y": "$FINAL_CCD_Y"
    },
    "fits_files": $FITS_INFO,
    "context_exists": $CONTEXT_EXISTS_PY
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="