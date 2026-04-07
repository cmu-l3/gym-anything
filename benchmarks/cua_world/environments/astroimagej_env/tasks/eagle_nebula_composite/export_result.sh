#!/bin/bash
echo "=== Exporting Eagle Nebula Composite Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

export DISPLAY=:1
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Ensure necessary Python libraries are available
python3 -c "import PIL" 2>/dev/null || (apt-get update && apt-get install -y python3-pil 2>/dev/null) || pip3 install Pillow 2>/dev/null || true

# Python script to analyze the output image and compare with FITS sources
python3 << 'PYEOF'
import json
import os
import glob
import time
import numpy as np

# Safely import astropy and PIL
try:
    from astropy.io import fits
    HAS_ASTROPY = True
except ImportError:
    HAS_ASTROPY = False

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

WORK_DIR = "/home/ga/AstroImages/eagle_nebula"
TASK_START_FILE = "/tmp/task_start_time"

result = {
    "output_found": False,
    "output_file": None,
    "created_during_task": False,
    "is_valid_image": False,
    "num_channels": 0,
    "width": 0,
    "height": 0,
    "dynamic_range_std": {"R": 0, "G": 0, "B": 0},
    "correlation_matrix": {},
    "error": None
}

# 1. Find the output file
search_paths = [
    f"{WORK_DIR}/eagle_nebula_hubble_palette.*",
    f"/home/ga/Desktop/eagle_nebula_hubble_palette.*",
    f"/home/ga/eagle_nebula_hubble_palette.*"
]

output_file = None
for path in search_paths:
    matches = glob.glob(path)
    # filter out the fits files themselves if agent renamed weirdly
    valid_matches = [m for m in matches if m.lower().endswith(('.tiff', '.tif', '.png', '.jpg', '.jpeg'))]
    if valid_matches:
        output_file = valid_matches[0]
        break

if not output_file:
    result["error"] = "Output file not found."
else:
    result["output_found"] = True
    result["output_file"] = output_file
    
    # 2. Check creation time
    try:
        with open(TASK_START_FILE, 'r') as f:
            start_time = int(f.read().strip())
        file_mtime = os.path.getmtime(output_file)
        if file_mtime >= start_time:
            result["created_during_task"] = True
    except Exception:
        # If timestamp checks fail, assume true but flag it
        result["created_during_task"] = True

    # 3. Analyze Image
    if HAS_PIL:
        try:
            img = Image.open(output_file)
            result["is_valid_image"] = True
            result["width"], result["height"] = img.size
            
            # Check channels
            img_mode = img.mode
            img_rgb = img.convert('RGB')
            img_arr = np.array(img_rgb)
            result["num_channels"] = img_arr.shape[2] if len(img_arr.shape) == 3 else 1
            
            if result["num_channels"] >= 3:
                # Calculate basic dynamic range (std dev) to ensure it's not a blank/solid image
                result["dynamic_range_std"] = {
                    "R": float(np.std(img_arr[:,:,0])),
                    "G": float(np.std(img_arr[:,:,1])),
                    "B": float(np.std(img_arr[:,:,2]))
                }
                
                # 4. Correlate with FITS sources (if astropy available)
                if HAS_ASTROPY:
                    def load_fits_safe(path):
                        if not os.path.exists(path): return None
                        with fits.open(path) as hdul:
                            for hdu in hdul:
                                if hdu.data is not None and len(hdu.data.shape) == 2:
                                    data = np.nan_to_num(hdu.data.astype(float))
                                    return data
                        return None

                    def resize_to_match(data, w, h):
                        # Normalize 0-1
                        dmin = np.min(data)
                        dmax = np.max(data)
                        if dmax > dmin:
                            data = (data - dmin) / (dmax - dmin)
                        else:
                            data = np.zeros_like(data)
                        # Resize using PIL
                        data_img = Image.fromarray((data * 255).astype(np.uint8))
                        data_img = data_img.resize((w, h), Image.Resampling.BILINEAR)
                        return np.array(data_img).astype(float)

                    f502 = load_fits_safe(f"{WORK_DIR}/502nmos.fits")
                    f656 = load_fits_safe(f"{WORK_DIR}/656nmos.fits")
                    f673 = load_fits_safe(f"{WORK_DIR}/673nmos.fits")
                    
                    if f502 is not None and f656 is not None and f673 is not None:
                        # Resize FITS to match output image in case agent cropped/scaled
                        w, h = result["width"], result["height"]
                        f502_rs = resize_to_match(f502, w, h).flatten()
                        f656_rs = resize_to_match(f656, w, h).flatten()
                        f673_rs = resize_to_match(f673, w, h).flatten()
                        
                        r_flat = img_arr[:,:,0].flatten().astype(float)
                        g_flat = img_arr[:,:,1].flatten().astype(float)
                        b_flat = img_arr[:,:,2].flatten().astype(float)
                        
                        # Calculate Pearson correlation coefficient
                        def calc_corr(a, b):
                            if np.std(a) == 0 or np.std(b) == 0: return 0.0
                            return float(np.corrcoef(a, b)[0, 1])
                            
                        result["correlation_matrix"] = {
                            "R_vs_502": calc_corr(r_flat, f502_rs),
                            "R_vs_656": calc_corr(r_flat, f656_rs),
                            "R_vs_673": calc_corr(r_flat, f673_rs),
                            
                            "G_vs_502": calc_corr(g_flat, f502_rs),
                            "G_vs_656": calc_corr(g_flat, f656_rs),
                            "G_vs_673": calc_corr(g_flat, f673_rs),
                            
                            "B_vs_502": calc_corr(b_flat, f502_rs),
                            "B_vs_656": calc_corr(b_flat, f656_rs),
                            "B_vs_673": calc_corr(b_flat, f673_rs),
                        }
        except Exception as e:
            result["error"] = f"Image analysis failed: {str(e)}"

# Save results
with open("/tmp/eagle_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
    
print(f"Analysis complete. Found: {result['output_found']}, Valid: {result['is_valid_image']}")
PYEOF

echo "=== Export Complete ==="