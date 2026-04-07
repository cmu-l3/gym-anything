#!/bin/bash
set -e

echo "=== Exporting RGB Composite Result ==="
source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Analyze output and compute channel correlation inside the container
# This uses container dependencies (numpy/astropy/PIL) efficiently.
cat > /tmp/analyze_composite.py << 'PYEOF'
import json, os, sys
import numpy as np
from PIL import Image

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

out_file = "/home/ga/AstroImages/processed/eagle_nebula_hubble_palette.png"
work_dir = "/home/ga/AstroImages/eagle_nebula"
start_time = int(sys.argv[1]) if len(sys.argv) > 1 else 0

res = {
    "output_exists": False,
    "created_during_task": False,
    "format": None,
    "mode": None,
    "width": 0,
    "height": 0,
    "is_color": False,
    "correlations": {
        "R": {"SII": 0, "Ha": 0, "OIII": 0},
        "G": {"SII": 0, "Ha": 0, "OIII": 0},
        "B": {"SII": 0, "Ha": 0, "OIII": 0}
    },
    "error": None
}

if os.path.exists(out_file):
    res["output_exists"] = True
    mtime = os.path.getmtime(out_file)
    res["created_during_task"] = mtime > start_time

    try:
        img = Image.open(out_file)
        res["format"] = img.format
        res["mode"] = img.mode
        res["width"], res["height"] = img.size

        # Convert to RGB numpy array for analysis
        img_rgb = img.convert("RGB")
        img_arr = np.array(img_rgb)

        # Check if the image is actually color (differentiating R, G, B channels)
        diff_rg = np.std(img_arr[:,:,0].astype(float) - img_arr[:,:,1].astype(float))
        diff_gb = np.std(img_arr[:,:,1].astype(float) - img_arr[:,:,2].astype(float))
        res["is_color"] = float(diff_rg) > 2.0 or float(diff_gb) > 2.0

        if HAS_ASTROPY:
            def get_correlation(ch_arr, fits_file):
                try:
                    fits_path = os.path.join(work_dir, fits_file)
                    if not os.path.exists(fits_path):
                        return 0.0
                    
                    with fits.open(fits_path) as hdul:
                        fdata = hdul[0].data
                        fdata = np.nan_to_num(fdata)
                        
                        # Match dimensions (agent might crop slightly during save)
                        if (ch_arr.shape[1], ch_arr.shape[0]) != (fdata.shape[1], fdata.shape[0]):
                            img_resized = Image.fromarray(ch_arr).resize(
                                (fdata.shape[1], fdata.shape[0]), Image.Resampling.BILINEAR
                            )
                            ch_data = np.array(img_resized).astype(float)
                        else:
                            ch_data = ch_arr.astype(float)

                        c_flat = ch_data.flatten()
                        f_flat = fdata.flatten()
                        
                        # Compute Pearson correlation
                        c_std = np.std(c_flat)
                        f_std = np.std(f_flat)
                        if c_std == 0 or f_std == 0:
                            return 0.0
                            
                        c_norm = (c_flat - np.mean(c_flat)) / c_std
                        f_norm = (f_flat - np.mean(f_flat)) / f_std
                        return float(np.mean(c_norm * f_norm))
                except Exception as e:
                    return 0.0

            # Red Channel mapping check
            res["correlations"]["R"]["SII"] = get_correlation(img_arr[:,:,0], "673nmos.fits")
            res["correlations"]["R"]["Ha"] = get_correlation(img_arr[:,:,0], "656nmos.fits")
            res["correlations"]["R"]["OIII"] = get_correlation(img_arr[:,:,0], "502nmos.fits")

            # Green Channel mapping check
            res["correlations"]["G"]["SII"] = get_correlation(img_arr[:,:,1], "673nmos.fits")
            res["correlations"]["G"]["Ha"] = get_correlation(img_arr[:,:,1], "656nmos.fits")
            res["correlations"]["G"]["OIII"] = get_correlation(img_arr[:,:,1], "502nmos.fits")

            # Blue Channel mapping check
            res["correlations"]["B"]["SII"] = get_correlation(img_arr[:,:,2], "673nmos.fits")
            res["correlations"]["B"]["Ha"] = get_correlation(img_arr[:,:,2], "656nmos.fits")
            res["correlations"]["B"]["OIII"] = get_correlation(img_arr[:,:,2], "502nmos.fits")

    except Exception as e:
        res["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f, indent=2)
PYEOF

python3 /tmp/analyze_composite.py "$TASK_START"

# Ensure proper permissions for verifier reading
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="