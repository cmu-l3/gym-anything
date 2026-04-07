#!/bin/bash
echo "=== Exporting Align and Crop Task Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
FINAL_SCREENSHOT="/tmp/task_end_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT" 2>/dev/null || DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || true

# ============================================================
# Analyze output using Python
# ============================================================
python3 << 'PYEOF'
import os
import glob
import json
import numpy as np
from astropy.io import fits
from scipy.signal import correlate2d

OUT_DIR = "/home/ga/AstroImages/aligned_sequence"

result = {
    "output_file_count": 0,
    "dimensions": None,
    "is_cropped": False,
    "shift_magnitude_px": None,
    "edge_zeros_detected": False,
    "data_integrity_std": 0.0,
    "error": None
}

try:
    # 1. Count output files
    out_files = sorted(glob.glob(os.path.join(OUT_DIR, "*.fits")) + 
                       glob.glob(os.path.join(OUT_DIR, "*.fit")))
    result["output_file_count"] = len(out_files)
    
    if len(out_files) >= 2:
        # Load first and last frame
        d0 = fits.getdata(out_files[0]).astype(float)
        d_last = fits.getdata(out_files[-1]).astype(float)
        
        # 2. Check dimensions / crop
        h, w = d0.shape
        result["dimensions"] = [h, w]
        if h < 4096 and w < 4096:
            result["is_cropped"] = True
            
        # 3. Check for edge zeros (padding artifacts)
        # Check boundary rows and columns
        edges = np.concatenate([d0[0, :], d0[-1, :], d0[:, 0], d0[:, -1]])
        if np.any(edges == 0.0):
            result["edge_zeros_detected"] = True
            
        # 4. Data integrity (ensure they didn't just duplicate frame 0)
        diff_std = float(np.std(d_last - d0))
        result["data_integrity_std"] = diff_std
        
        # 5. Measure alignment shift via cross-correlation of center patch
        # Use a 200x200 patch from the center to compute shift
        ch, cw = h // 2, w // 2
        psize = 100
        
        # Ensure we have enough image to crop a patch
        if h > 250 and w > 250:
            p0 = d0[ch-psize:ch+psize, cw-psize:cw+psize]
            p_last = d_last[ch-psize:ch+psize, cw-psize:cw+psize]
            
            p0 = p0 - np.mean(p0)
            p_last = p_last - np.mean(p_last)
            
            # Cross-correlate
            corr = correlate2d(p0, p_last, mode='same')
            y, x = np.unravel_index(np.argmax(corr), corr.shape)
            
            # Distance from center
            dy = y - psize
            dx = x - psize
            shift_mag = float(np.sqrt(dx**2 + dy**2))
            
            result["shift_magnitude_px"] = shift_mag

except Exception as e:
    result["error"] = str(e)

# Save results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="