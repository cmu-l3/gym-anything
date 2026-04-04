#!/bin/bash
echo "=== Exporting image registration results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/registration"
RAW_DIR="/home/ga/Fiji_Data/raw/registration"
GT_FILE="/var/lib/registration_ground_truth/ground_truth.json"
RESULT_JSON="/tmp/task_result.json"

# Python script to analyze results
python3 << PYEOF
import json
import os
import numpy as np
from PIL import Image
import re

results_dir = "$RESULTS_DIR"
raw_dir = "$RAW_DIR"
gt_file = "$GT_FILE"
out_file = "$RESULT_JSON"

data = {
    "registered_exists": False,
    "difference_exists": False,
    "report_exists": False,
    "registered_valid": False,
    "ncc_final": 0.0,
    "ncc_baseline": 0.0,
    "mad_final": 0.0,
    "mad_baseline": 0.0,
    "is_copy": False,
    "reported_tx": None,
    "reported_ty": None,
    "reported_rot": None,
    "ground_truth": {}
}

# Load ground truth
if os.path.exists(gt_file):
    with open(gt_file, 'r') as f:
        data["ground_truth"] = json.load(f)
        data["ncc_baseline"] = data["ground_truth"].get("ncc_before", 0.0)

# Check files
reg_path = os.path.join(results_dir, "registered_micrograph.tif")
diff_path = os.path.join(results_dir, "difference_image.tif")
rep_path = os.path.join(results_dir, "alignment_report.txt")

# Handle extensions
if not os.path.exists(reg_path):
    for ext in ['.png', '.jpg', '.tiff']:
        if os.path.exists(os.path.join(results_dir, "registered_micrograph" + ext)):
            reg_path = os.path.join(results_dir, "registered_micrograph" + ext)
            break

if not os.path.exists(diff_path):
    for ext in ['.png', '.jpg', '.tiff']:
        if os.path.exists(os.path.join(results_dir, "difference_image" + ext)):
            diff_path = os.path.join(results_dir, "difference_image" + ext)
            break

data["registered_exists"] = os.path.exists(reg_path)
data["difference_exists"] = os.path.exists(diff_path)
data["report_exists"] = os.path.exists(rep_path)

# Image Analysis
if data["registered_exists"]:
    try:
        ref_path = os.path.join(raw_dir, "reference_micrograph.tif")
        shift_path = os.path.join(raw_dir, "shifted_micrograph.tif")
        
        ref = np.array(Image.open(ref_path).convert("L")).astype(float)
        reg = np.array(Image.open(reg_path).convert("L")).astype(float)
        shift = np.array(Image.open(shift_path).convert("L")).astype(float)
        
        # Resize reg to match ref if needed (sometimes agents save screenshot or wrong size)
        if reg.shape != ref.shape:
            # Simple check: if size mismatch is small, just crop/pad? 
            # If huge, invalid.
            if abs(reg.shape[0] - ref.shape[0]) < 10 and abs(reg.shape[1] - ref.shape[1]) < 10:
                # Crop to min
                h = min(reg.shape[0], ref.shape[0])
                w = min(reg.shape[1], ref.shape[1])
                ref = ref[:h, :w]
                reg = reg[:h, :w]
                shift = shift[:h, :w]
            else:
                data["registered_valid"] = False
        
        if reg.shape == ref.shape:
            data["registered_valid"] = True
            
            # Crop margins for metric calculation (20px)
            m = 20
            r_c = ref[m:-m, m:-m]
            g_c = reg[m:-m, m:-m]
            s_c = shift[m:-m, m:-m]
            
            # NCC Final
            if r_c.std() > 0 and g_c.std() > 0:
                data["ncc_final"] = float(np.corrcoef(r_c.flatten(), g_c.flatten())[0, 1])
            
            # MAD Final
            data["mad_final"] = float(np.mean(np.abs(r_c - g_c)))
            
            # MAD Baseline
            data["mad_baseline"] = float(np.mean(np.abs(r_c - s_c)))
            
            # Anti-gaming: Check if registered is identical to shifted
            # Correlation between registered and shifted
            corr_copy = 0
            if g_c.std() > 0 and s_c.std() > 0:
                corr_copy = np.corrcoef(g_c.flatten(), s_c.flatten())[0, 1]
            
            if corr_copy > 0.999:
                data["is_copy"] = True
                
    except Exception as e:
        print(f"Error analyzing images: {e}")

# Parse Report
if data["report_exists"]:
    try:
        with open(rep_path, 'r') as f:
            content = f.read().lower()
        
        # Regex for numbers
        # Look for X, Y, Rotation
        # Patterns: "Translation X: 23", "X: 23", "dx: 23"
        
        tx_match = re.search(r'(?:x|dx|horizontal).*?[:=]\s*([+-]?\d+\.?\d*)', content)
        ty_match = re.search(r'(?:y|dy|vertical).*?[:=]\s*([+-]?\d+\.?\d*)', content)
        rot_match = re.search(r'(?:rot|angle|deg).*?[:=]\s*([+-]?\d+\.?\d*)', content)
        
        if tx_match: data["reported_tx"] = float(tx_match.group(1))
        if ty_match: data["reported_ty"] = float(ty_match.group(1))
        if rot_match: data["reported_rot"] = float(rot_match.group(1))
        
    except Exception as e:
        print(f"Error parsing report: {e}")

# Write result
with open(out_file, 'w') as f:
    json.dump(data, f, indent=2)

print("Analysis complete.")
PYEOF

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="