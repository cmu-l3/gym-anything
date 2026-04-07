#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Python script to analyze FITS and parse TXT
python3 << 'PYEOF'
import json, os, re
import numpy as np

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

result = {
    "crop_fits_exists": False,
    "surface_png_exists": False,
    "stats_txt_exists": False,
    "crop_width": 0,
    "crop_height": 0,
    "actual_peak_value": 0,
    "actual_peak_x": 0,
    "actual_peak_y": 0,
    "is_valid_star": False,
    "reported_width": None,
    "reported_height": None,
    "reported_peak_value": None,
    "reported_peak_x": None,
    "reported_peak_y": None,
    "stats_formatted": False
}

crop_fits = "/home/ga/AstroImages/processed/psf_crop.fits"
if os.path.exists(crop_fits):
    result["crop_fits_exists"] = True
    if HAS_ASTROPY:
        try:
            with fits.open(crop_fits) as hdul:
                data = hdul[0].data
                if data is not None:
                    # Strip any extra dimensions astropy leaves behind
                    if data.ndim > 2:
                        data = data.reshape(-1, data.shape[-1])[:data.shape[-2], :]
                    
                    h, w = data.shape
                    result["crop_width"] = w
                    result["crop_height"] = h
                    
                    # Compute actual peak values
                    peak_val = float(np.nanmax(data))
                    result["actual_peak_value"] = peak_val
                    
                    # Compute peak coordinates (y, x mapping to matches ImageJ's indexing)
                    y_idx, x_idx = np.unravel_index(np.nanargmax(data), data.shape)
                    result["actual_peak_x"] = int(x_idx)
                    result["actual_peak_y"] = int(y_idx)
                    
                    median = float(np.nanmedian(data))
                    std = float(np.nanstd(data))
                    
                    # Validate crop has a distinctly bright central peak and is not directly on the edge
                    is_peak_bright = peak_val > (median + 3 * std)
                    not_on_edge = (x_idx > 1) and (x_idx < w - 2) and (y_idx > 1) and (y_idx < h - 2)
                    
                    result["is_valid_star"] = bool(is_peak_bright and not_on_edge)
        except Exception as e:
            result["fits_error"] = str(e)

surface_png = "/home/ga/AstroImages/processed/psf_surface.png"
if os.path.exists(surface_png):
    result["surface_png_exists"] = True

stats_txt = "/home/ga/AstroImages/processed/psf_stats.txt"
if os.path.exists(stats_txt):
    result["stats_txt_exists"] = True
    try:
        with open(stats_txt, 'r') as f:
            content = f.read()
        
        # Regex helper forgiving of colons/spaces
        def extract_val(pattern):
            m = re.search(pattern, content, re.IGNORECASE)
            return float(m.group(1)) if m else None
            
        w = extract_val(r'crop_width[\s:=]+([0-9.]+)')
        h = extract_val(r'crop_height[\s:=]+([0-9.]+)')
        pv = extract_val(r'peak_value[\s:=]+([0-9.]+)')
        px = extract_val(r'peak_x[\s:=]+([0-9.]+)')
        py = extract_val(r'peak_y[\s:=]+([0-9.]+)')
        
        result["reported_width"] = w
        result["reported_height"] = h
        result["reported_peak_value"] = pv
        result["reported_peak_x"] = px
        result["reported_peak_y"] = py
        
        if all(v is not None for v in [w, h, pv, px, py]):
            result["stats_formatted"] = True
            
    except Exception as e:
        result["stats_error"] = str(e)

# Create JSON result
temp_json = "/tmp/result_tmp.json"
with open(temp_json, "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Safely copy to destination to avoid permission issues
cp /tmp/result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/result_tmp.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="