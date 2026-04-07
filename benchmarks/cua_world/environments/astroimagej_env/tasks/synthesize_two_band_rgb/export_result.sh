#!/bin/bash
echo "=== Exporting Synthesize Two-Band RGB Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We will run a Python script inside the container to perform math integrity checks
# This avoids transferring ~50MB of FITS files back to the host.
python3 << 'PYEOF'
import json
import os
import glob
try:
    from astropy.io import fits
    import numpy as np
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

PROJECT_DIR = "/home/ga/AstroImages/outreach"
GREEN_PATH = os.path.join(PROJECT_DIR, "synthetic_green.fits")
B_PATH = os.path.join(PROJECT_DIR, "Bcomb.fits")
V_PATH = os.path.join(PROJECT_DIR, "Vcomb.fits")

result = {
    "green_exists": False,
    "green_math_correct": False,
    "max_error": None,
    "rgb_exists": False,
    "rgb_channels": 0,
    "rgb_created_during_task": False,
    "astropy_available": HAS_ASTROPY
}

# 1. Check Math Integrity of the FITS file
if os.path.exists(GREEN_PATH):
    result["green_exists"] = True
    if HAS_ASTROPY and os.path.exists(B_PATH) and os.path.exists(V_PATH):
        try:
            with fits.open(GREEN_PATH) as hdul_g:
                data_g = hdul_g[0].data.astype(float)
            with fits.open(B_PATH) as hdul_b:
                data_b = hdul_b[0].data.astype(float)
            with fits.open(V_PATH) as hdul_v:
                data_v = hdul_v[0].data.astype(float)
            
            # Ground truth formula
            expected_g = (data_b + data_v) / 2.0
            
            # Check difference (ignoring NaNs to be safe)
            valid = np.isfinite(expected_g) & np.isfinite(data_g)
            if np.any(valid):
                max_err = np.max(np.abs(data_g[valid] - expected_g[valid]))
                result["max_error"] = float(max_err)
                
                # Allow a small tolerance for 32-bit float truncation
                # Astronomical pixel values can be large (e.g., 65000), so 1.0 is a tight tolerance
                if max_err < 1.0:
                    result["green_math_correct"] = True
            else:
                result["error_math"] = "No valid finite pixels to compare."
        except Exception as e:
            result["error_math"] = str(e)

# 2. Check RGB Composite File
rgb_files = glob.glob(os.path.join(PROJECT_DIR, "m12_color_composite.*"))
if rgb_files:
    rgb_file = rgb_files[0]
    result["rgb_exists"] = True
    
    # Check creation time to prevent gaming
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            task_start = int(f.read().strip())
        if os.path.getmtime(rgb_file) > task_start:
            result["rgb_created_during_task"] = True
    except:
        pass
        
    # Check if it's actually an RGB image (using PIL if available)
    try:
        from PIL import Image
        img = Image.open(rgb_file)
        result["rgb_channels"] = len(img.getbands())
        result["rgb_format"] = img.format
    except Exception as e:
        result["error_rgb"] = str(e)
        # Fallback check by extension
        if rgb_file.lower().endswith(('.tif', '.tiff', '.png', '.jpg', '.jpeg')):
            result["rgb_channels"] = 3  # Assume 3 if valid extension and PIL failed

# Write to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="