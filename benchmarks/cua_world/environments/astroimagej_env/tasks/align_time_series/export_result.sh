#!/bin/bash
set -euo pipefail

echo "=== Exporting align_time_series task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/AstroImages/processed/aligned_stack.fits"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic file existence and timestamp checks
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED="true"
    else
        FILE_CREATED="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_CREATED="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
fi

# Write base JSON
cat > /tmp/task_result_base.json << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $(pgrep -f "astroimagej\|aij" > /dev/null && echo "true" || echo "false")
}
EOF

# 3. Deep FITS Analysis (Run inside container where astropy/scipy are guaranteed)
cat > /tmp/analyze_fits.py << 'EOF'
import json
import os
import numpy as np
from astropy.io import fits
from scipy.signal import fftconvolve

def analyze():
    result = {
        "fits_analyzed": False,
        "error": None,
        "shape": [],
        "variance": 0.0,
        "shift_x": 999.0,
        "shift_y": 999.0,
        "shift_magnitude": 999.0
    }
    
    fits_path = "/home/ga/AstroImages/processed/aligned_stack.fits"
    if not os.path.exists(fits_path):
        result["error"] = "File not found"
        return result

    try:
        with fits.open(fits_path) as hdul:
            data = None
            for hdu in hdul:
                if hdu.data is not None and len(hdu.data.shape) >= 2:
                    data = hdu.data
                    break
            
            if data is None:
                result["error"] = "No image data found in FITS"
                return result

            result["shape"] = list(data.shape)
            
            # Must be a 3D cube (stack) and have at least 2 frames
            if len(data.shape) == 3 and data.shape[0] >= 2:
                f0 = data[0].astype(float)
                f_last = data[-1].astype(float)
                
                # Variance check to prevent anti-gaming (duplicating frame 1)
                diff = f0 - f_last
                result["variance"] = float(np.var(diff))
                
                # Cross correlation for shift detection (crop center 200x200 for speed)
                h, w = f0.shape
                cy, cx = h//2, w//2
                sy, ey = max(0, cy-150), min(h, cy+150)
                sx, ex = max(0, cx-150), min(w, cx+150)
                
                c0 = f0[sy:ey, sx:ex]
                clast = f_last[sy:ey, sx:ex]
                
                c0_norm = c0 - np.median(c0)
                clast_norm = clast - np.median(clast)
                
                # Phase cross correlation via FFT
                corr = fftconvolve(c0_norm, clast_norm[::-1, ::-1], mode='same')
                max_idx = np.unravel_index(np.argmax(corr), corr.shape)
                
                center_y = corr.shape[0] // 2
                center_x = corr.shape[1] // 2
                
                shift_y = max_idx[0] - center_y
                shift_x = max_idx[1] - center_x
                
                result["shift_y"] = float(shift_y)
                result["shift_x"] = float(shift_x)
                result["shift_magnitude"] = float(np.sqrt(shift_y**2 + shift_x**2))
                result["fits_analyzed"] = True
            else:
                result["error"] = "Data is not a 3D FITS cube stack"
                
    except Exception as e:
        result["error"] = str(e)

    return result

if __name__ == "__main__":
    res = analyze()
    with open("/tmp/fits_analysis.json", "w") as f:
        json.dump(res, f)
EOF

sudo -u ga python3 /tmp/analyze_fits.py

# 4. Merge JSON files
python3 << 'EOF'
import json
with open('/tmp/task_result_base.json') as f:
    base = json.load(f)
try:
    with open('/tmp/fits_analysis.json') as f:
        fits_data = json.load(f)
        base.update(fits_data)
except Exception as e:
    base["fits_analyzed"] = False
    base["error"] = f"Failed to merge fits analysis: {e}"

with open('/tmp/task_result.json', 'w') as f:
    json.dump(base, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="