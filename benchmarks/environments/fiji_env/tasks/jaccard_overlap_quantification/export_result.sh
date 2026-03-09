#!/bin/bash
echo "=== Exporting Jaccard Overlap Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/jaccard"
RAW_DIR="/home/ga/Fiji_Data/raw/jaccard"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will run a Python script inside the environment to validate the images.
# This ensures we use the environment's libraries (numpy, skimage) to calculate Ground Truth.
cat > /tmp/validate_jaccard.py << 'EOF'
import os
import sys
import json
import csv
import numpy as np
from PIL import Image
from skimage.filters import threshold_otsu

def load_image_gray(path):
    if not os.path.exists(path):
        return None
    try:
        img = Image.open(path).convert('L')
        return np.array(img)
    except Exception as e:
        return None

def calculate_ground_truth(img1_path, img2_path):
    img1 = load_image_gray(img1_path)
    img2 = load_image_gray(img2_path)
    
    if img1 is None or img2 is None:
        return None

    # Apply Otsu
    thresh1 = threshold_otsu(img1)
    thresh2 = threshold_otsu(img2)
    
    mask1 = img1 > thresh1
    mask2 = img2 > thresh2
    
    intersection = np.logical_and(mask1, mask2)
    union = np.logical_or(mask1, mask2)
    
    area_int = np.sum(intersection)
    area_union = np.sum(union)
    
    jaccard = area_int / area_union if area_union > 0 else 0
    return {
        "jaccard": float(jaccard),
        "intersection_area": int(area_int),
        "union_area": int(area_union),
        "mask1_shape": mask1.shape
    }

def compare_masks(gt_img_path, agent_mask_path, op_type="intersection"):
    # Load agent mask
    agent_mask_arr = load_image_gray(agent_mask_path)
    if agent_mask_arr is None:
        return 0.0
        
    # Re-calculate GT mask
    img1 = load_image_gray(sys.argv[1])
    img2 = load_image_gray(sys.argv[2])
    thresh1 = threshold_otsu(img1)
    thresh2 = threshold_otsu(img2)
    mask1 = img1 > thresh1
    mask2 = img2 > thresh2
    
    if op_type == "intersection":
        gt_mask = np.logical_and(mask1, mask2)
    else:
        gt_mask = np.logical_or(mask1, mask2)
        
    # Agent mask might be 0/255, convert to boolean
    # Handle potentially inverted masks or 0/255 scaling
    agent_bool = agent_mask_arr > 128
    
    # Calculate IoU between Agent Mask and GT Mask (Mask-IoU)
    # This verifies the mask image itself is correct
    intersection = np.logical_and(agent_bool, gt_mask)
    union = np.logical_or(agent_bool, gt_mask)
    
    score = np.sum(intersection) / np.sum(union) if np.sum(union) > 0 else 0
    return float(score)

# Main Execution
raw_dir = sys.argv[3]
results_dir = sys.argv[4]

img1_path = os.path.join(raw_dir, "channel_1.tif")
img2_path = os.path.join(raw_dir, "channel_2.tif")

# 1. Calculate Ground Truth
gt = calculate_ground_truth(img1_path, img2_path)

result_data = {
    "ground_truth": gt,
    "files_found": {},
    "agent_reported": {},
    "mask_accuracy": {}
}

# 2. Check Agent Files
files = ["intersection_mask.tif", "union_mask.tif", "results.csv"]
for f in files:
    fpath = os.path.join(results_dir, f)
    exists = os.path.exists(fpath)
    result_data["files_found"][f] = exists
    
    if exists:
        mtime = os.path.getmtime(fpath)
        # Check against task start time passed as arg
        result_data["files_found"][f + "_new"] = mtime > int(sys.argv[5])

# 3. Verify Masks (if they exist)
if result_data["files_found"].get("intersection_mask.tif"):
    acc = compare_masks(None, os.path.join(results_dir, "intersection_mask.tif"), "intersection")
    result_data["mask_accuracy"]["intersection"] = acc

if result_data["files_found"].get("union_mask.tif"):
    acc = compare_masks(None, os.path.join(results_dir, "union_mask.tif"), "union")
    result_data["mask_accuracy"]["union"] = acc

# 4. Parse CSV
csv_path = os.path.join(results_dir, "results.csv")
if os.path.exists(csv_path):
    try:
        with open(csv_path, 'r') as f:
            # Try to handle headerless or headered CSV
            content = f.read().strip().splitlines()
            if content:
                # Naive parser: look for numbers in the last line
                last_line = content[-1]
                parts = last_line.split(',')
                # Expecting: jaccard, intersection, union
                # Try to find the float 0.0-1.0
                for p in parts:
                    try:
                        val = float(p.strip())
                        if 0 <= val <= 1.0:
                            result_data["agent_reported"]["jaccard"] = val
                        elif val > 1.0:
                             # Assume larger numbers are areas
                             pass
                    except:
                        pass
    except Exception as e:
        result_data["csv_error"] = str(e)

print(json.dumps(result_data))
EOF

# Run the python validation script
# Arguments: img1, img2, raw_dir, results_dir, task_start_time
python3 /tmp/validate_jaccard.py \
    "$RAW_DIR/channel_1.tif" \
    "$RAW_DIR/channel_2.tif" \
    "$RAW_DIR" \
    "$RESULTS_DIR" \
    "$TASK_START" > /tmp/task_result.json

# Cleanup
rm /tmp/validate_jaccard.py

# Final screenshot info
echo "Screenshot saved to /tmp/task_final.png"

echo "=== Export complete ==="
cat /tmp/task_result.json