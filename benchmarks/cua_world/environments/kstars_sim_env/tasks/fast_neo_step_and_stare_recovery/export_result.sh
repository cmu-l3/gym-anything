#!/bin/bash
echo "=== Exporting fast_neo_step_and_stare_recovery results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TRACKING_DIR="/home/ga/Images/neo_tracking"

# 2. Extract FITS File info
FITS_INFO=$(python3 -c "
import os, json, glob

upload_dir = '$TRACKING_DIR'
files = []

for pattern in [upload_dir + '/*.fits', upload_dir + '/*.fit']:
    for f in glob.glob(pattern):
        try:
            stat = os.stat(f)
            ra_val, dec_val, filt, exptime = '', '', '', -1
            try:
                from astropy.io import fits as pyfits
                with pyfits.open(f) as hdul:
                    h = hdul[0].header
                    filt = str(h.get('FILTER', h.get('FILTER2', ''))).strip()
                    ra_val = str(h.get('OBJCTRA', h.get('RA', ''))).strip()
                    dec_val = str(h.get('OBJCTDEC', h.get('DEC', ''))).strip()
                    exptime = float(h.get('EXPTIME', -1))
            except Exception:
                pass
                
            files.append({
                'name': os.path.basename(f),
                'path': f,
                'size': stat.st_size,
                'mtime': stat.st_mtime,
                'ra': ra_val,
                'dec': dec_val,
                'filter': filt,
                'exptime': exptime
            })
        except Exception:
            pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# 3. Check Animated GIF
GIF_PATH="$TRACKING_DIR/neo_animation.gif"
GIF_EXISTS="false"
GIF_MTIME=0
GIF_SIZE=0
GIF_FRAMES=0
GIF_DURATION=0
GIF_LOOP=-1

if [ -f "$GIF_PATH" ]; then
    GIF_EXISTS="true"
    GIF_MTIME=$(stat -c %Y "$GIF_PATH" 2>/dev/null || echo "0")
    GIF_SIZE=$(stat -c %s "$GIF_PATH" 2>/dev/null || echo "0")
    
    # Extract GIF properties via Python
    GIF_PROPS=$(python3 -c "
import json
try:
    from PIL import Image
    gif = Image.open('$GIF_PATH')
    frames = getattr(gif, 'n_frames', 1)
    duration = gif.info.get('duration', 0)
    loop = gif.info.get('loop', -1)
    print(json.dumps({'frames': frames, 'duration': duration, 'loop': loop}))
except Exception:
    print(json.dumps({'frames': 0, 'duration': 0, 'loop': -1}))
" 2>/dev/null || echo '{"frames": 0, "duration": 0, "loop": -1}')

    GIF_FRAMES=$(echo "$GIF_PROPS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('frames', 0))")
    GIF_DURATION=$(echo "$GIF_PROPS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('duration', 0))")
    GIF_LOOP=$(echo "$GIF_PROPS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('loop', -1))")
fi

GIF_EXISTS_PY=$([ "$GIF_EXISTS" = "true" ] && echo "True" || echo "False")

# 4. Generate JSON Report
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "gif": {
        "exists": $GIF_EXISTS_PY,
        "mtime": $GIF_MTIME,
        "size": $GIF_SIZE,
        "frames": $GIF_FRAMES,
        "duration": $GIF_DURATION,
        "loop": $GIF_LOOP
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="