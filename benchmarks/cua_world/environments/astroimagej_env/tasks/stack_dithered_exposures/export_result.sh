#!/bin/bash
echo "=== Exporting Stack Dithered Exposures Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before anything is closed
take_screenshot /tmp/task_end_screenshot.png

# Analyze the results via Python
python3 << 'PYEOF'
import json
import os
import sys
import numpy as np
from astropy.io import fits
from scipy import ndimage

def measure_quality(data):
    """Measures FWHM, ellipticity, and background noise of an image."""
    # Estimate background using robust statistics
    bg_med = np.nanmedian(data)
    bg_std = np.nanstd(data[(data < bg_med + np.nanstd(data)) & (data > bg_med - np.nanstd(data))])
    
    # Find stars (local maxima above threshold)
    threshold = bg_med + 5 * bg_std
    smoothed = ndimage.gaussian_filter(data, 2.0)
    labeled, num_features = ndimage.label(smoothed > threshold)
    
    if num_features < 2:
        return None
        
    # Get centroids of top bright regions
    centroids = ndimage.center_of_mass(data, labeled, range(1, min(num_features+1, 40)))
    
    fwhms = []
    ellipticities = []
    
    for cy, cx in centroids:
        y, x = int(cy), int(cx)
        if y < 15 or y > data.shape[0]-15 or x < 15 or x > data.shape[1]-15:
            continue
            
        # Extract small patch around star
        patch = data[y-15:y+16, x-15:x+16] - bg_med
        patch[patch < 0] = 0
        total = np.sum(patch)
        if total <= 0: continue
        
        # Calculate image moments
        Y, X = np.indices(patch.shape)
        x_c = np.sum(X * patch) / total
        y_c = np.sum(Y * patch) / total
        
        var_x = np.sum((X - x_c)**2 * patch) / total
        var_y = np.sum((Y - y_c)**2 * patch) / total
        cov_xy = np.sum((X - x_c)*(Y - y_c) * patch) / total
        
        # Eigenvalues of covariance matrix for ellipticity
        trace = var_x + var_y
        det = var_x * var_y - cov_xy**2
        discriminant = np.sqrt(max(0, trace**2 - 4*det))
        
        l1 = (trace + discriminant) / 2
        l2 = (trace - discriminant) / 2
        
        if l1 <= 0 or l2 <= 0: continue
        
        a = np.sqrt(l1)
        b = np.sqrt(l2)
        
        fwhm = 2.355 * np.sqrt((var_x + var_y)/2)
        ellipticity = 1.0 - (b / a)
        
        fwhms.append(fwhm)
        ellipticities.append(ellipticity)
        
    if not fwhms:
        return None
        
    return {
        "bg_mean": float(bg_med),
        "bg_std": float(bg_std),
        "fwhm_median": float(np.median(fwhms)),
        "ellipticity_median": float(np.median(ellipticities)),
        "stars_measured": len(fwhms)
    }

res = {
    "output_exists": False,
    "valid_fits": False,
    "ref_stats": None,
    "out_stats": None,
    "is_exact_copy": False,
    "file_mtime": 0
}

ref_path = "/home/ga/AstroImages/dithered_sequence/frame_001.fits"
out_path = "/home/ga/AstroImages/processed/master_stack.fits"

if os.path.exists(out_path):
    res["output_exists"] = True
    res["file_mtime"] = os.path.getmtime(out_path)
    
    try:
        out_data = fits.getdata(out_path).astype(np.float32)
        res["valid_fits"] = True
        
        ref_data = fits.getdata(ref_path).astype(np.float32)
        
        # Check if the agent just copied frame 1
        if np.array_equal(out_data, ref_data):
            res["is_exact_copy"] = True
            
        print("Measuring reference frame quality...")
        res["ref_stats"] = measure_quality(ref_data)
        
        print("Measuring master stack quality...")
        res["out_stats"] = measure_quality(out_data)
        
    except Exception as e:
        res["error"] = str(e)
        print(f"Error analyzing FITS: {e}")

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f, indent=2)
PYEOF

echo "Analysis complete. JSON written."
cat /tmp/task_result.json
echo "=== Export Complete ==="