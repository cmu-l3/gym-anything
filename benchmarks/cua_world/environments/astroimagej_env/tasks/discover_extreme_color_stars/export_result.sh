#!/bin/bash
echo "=== Exporting Discover Extreme Color Stars Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Run Python script to analyze the coordinates against actual FITS data
# We do this inside the container where Astropy and the data are natively available
python3 << 'PYEOF'
import json
import os
import re
import numpy as np

try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "parsed_coords": [],
    "candidates": [],
    "valid_candidates": 0,
    "error": None,
    "has_astropy": HAS_ASTROPY
}

c_file = "/home/ga/AstroImages/color_search/red_candidates.txt"

if os.path.exists(c_file):
    result["file_exists"] = True
    
    # Anti-gaming: Ensure file was created during the current task run
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = int(f.read().strip())
        if os.path.getmtime(c_file) >= start_time:
            result["file_created_during_task"] = True
    except Exception:
        pass
        
    try:
        with open(c_file, "r") as f:
            content = f.read()
        
        # Parse coordinate pairs
        coords = []
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            # Extract numbers from line
            nums = re.findall(r"[-+]?\d*\.\d+|\d+", line)
            if len(nums) >= 2:
                coords.append((float(nums[0]), float(nums[1])))
        
        result["parsed_coords"] = coords
        
        if HAS_ASTROPY and coords:
            v_file = "/home/ga/AstroImages/color_search/Vcomb.fits"
            b_file = "/home/ga/AstroImages/color_search/Bcomb.fits"
            
            if os.path.exists(v_file) and os.path.exists(b_file):
                v_data = fits.getdata(v_file).astype(float)
                b_data = fits.getdata(b_file).astype(float)
                
                # Estimate local background
                v_bg = np.nanmedian(v_data)
                b_bg = np.nanmedian(b_data)
                
                # Compute median color ratio of the entire field for baseline
                v_sub_all = v_data - v_bg
                b_sub_all = b_data - b_bg
                mask = v_sub_all > 100
                if np.any(mask):
                    ratios = v_sub_all[mask] / np.clip(b_sub_all[mask], 1, None)
                    field_median_ratio = float(np.median(ratios))
                else:
                    field_median_ratio = 1.0
                    
                result["field_median_ratio"] = field_median_ratio
                
                # Evaluate submitted candidates (up to 10 max to prevent brute force scraping)
                for (x, y) in coords[:10]:
                    ix, iy = int(round(x)), int(round(y))
                    cand_info = {"x": x, "y": y, "valid": False}
                    
                    if 1 <= iy < v_data.shape[0]-1 and 1 <= ix < v_data.shape[1]-1:
                        # 3x3 aperture sum
                        v_ap = v_data[iy-1:iy+2, ix-1:ix+2]
                        b_ap = b_data[iy-1:iy+2, ix-1:ix+2]
                        
                        v_flux = np.sum(v_ap) - 9 * v_bg
                        b_flux = np.sum(b_ap) - 9 * b_bg
                        
                        cand_info["v_flux"] = float(v_flux)
                        cand_info["b_flux"] = float(b_flux)
                        
                        # Star validity check: Is there a real source here? (Peak flux > background + 50)
                        if np.max(v_ap) > v_bg + 50 and v_flux > 100:
                            cand_info["is_star"] = True
                            ratio = v_flux / max(b_flux, 1.0)
                            cand_info["ratio"] = float(ratio)
                            
                            # Extreme color check: Must be 2.5x redder than field median
                            if ratio > field_median_ratio * 2.5:
                                cand_info["valid"] = True
                                result["valid_candidates"] += 1
                        else:
                            cand_info["is_star"] = False
                            
                    result["candidates"].append(cand_info)
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="