#!/bin/bash
echo "=== Exporting create_subitizing_experiment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# We use an embedded Python script to analyze the generated images INSIDE the container.
# This avoids needing to copy multiple image files out to the verifier.
# It uses scipy.ndimage to count dots and check for overlaps.

python3 << 'PYEOF'
import json
import os
import sys
import datetime
import csv
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image

try:
    from scipy import ndimage
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False

BASE_DIR = "/home/ga/PsychoPyExperiments/subitizing"
ASSETS_DIR = os.path.join(BASE_DIR, "assets")
SCRIPT_FILE = os.path.join(BASE_DIR, "generate_stimuli.py")
EXP_FILE = os.path.join(BASE_DIR, "subitizing_task.psyexp")
COND_FILE = os.path.join(BASE_DIR, "conditions.csv")
RESULT_FILE = "/tmp/subitizing_result.json"

results = {
    "timestamp": datetime.datetime.now().isoformat(),
    "script_exists": False,
    "script_content_check": False,
    "exp_exists": False,
    "cond_exists": False,
    "assets_exist": False,
    "image_analysis": {},
    "psyexp_structure": {},
    "cond_structure": {},
    "task_start_time": 0,
    "result_nonce": ""
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

# 1. Check Script
if os.path.exists(SCRIPT_FILE):
    results["script_exists"] = True
    try:
        with open(SCRIPT_FILE, 'r') as f:
            content = f.read()
            # Simple heuristic: does it check distance or overlap?
            if "distance" in content.lower() or "overlap" in content.lower() or "hypot" in content.lower() or "norm" in content.lower():
                results["script_content_check"] = True
    except:
        pass

# 2. Check Images (Computer Vision Check)
if os.path.exists(ASSETS_DIR):
    results["assets_exist"] = True
    if SCIPY_AVAILABLE:
        for i in range(1, 9):
            img_name = f"{i}.png"
            img_path = os.path.join(ASSETS_DIR, img_name)
            img_res = {"exists": False, "dots_found": 0, "pass": False}
            
            if os.path.exists(img_path):
                img_res["exists"] = True
                try:
                    # Open and convert to grayscale
                    img = Image.open(img_path).convert('L')
                    arr = np.array(img)
                    
                    # Thresholding to binary (assuming black dots on white or white on black)
                    # Detect background color
                    mean_val = np.mean(arr)
                    if mean_val > 128:
                        # White background, black dots -> invert
                        binary = arr < 128
                    else:
                        # Black background, white dots
                        binary = arr > 128
                        
                    # Label connected components
                    labeled, n_components = ndimage.label(binary)
                    img_res["dots_found"] = n_components
                    
                    # Pass if count matches filename
                    if n_components == i:
                        img_res["pass"] = True
                except Exception as e:
                    img_res["error"] = str(e)
            
            results["image_analysis"][str(i)] = img_res

# 3. Check Conditions File
if os.path.exists(COND_FILE):
    results["cond_exists"] = True
    try:
        with open(COND_FILE, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            results["cond_structure"]["row_count"] = len(rows)
            results["cond_structure"]["columns"] = reader.fieldnames
            
            # Check mappings
            correct_mappings = 0
            for row in rows:
                # Try to find image and key columns flexibly
                img_val = ""
                key_val = ""
                for k, v in row.items():
                    if "png" in str(v).lower():
                        img_val = v
                    if str(v).strip() in [str(n) for n in range(1, 9)]:
                        key_val = v
                
                # Verify logic: if image contains "3.png", key should be "3"
                for i in range(1, 9):
                    if f"{i}.png" in img_val and str(i) == str(key_val).strip():
                        correct_mappings += 1
            results["cond_structure"]["correct_mappings"] = correct_mappings
    except:
        pass

# 4. Check Experiment File (XML)
if os.path.exists(EXP_FILE):
    results["exp_exists"] = True
    try:
        tree = ET.parse(EXP_FILE)
        root = tree.getroot()
        
        # Check Image Component Duration
        image_duration = None
        images = []
        for img in root.findall(".//ImageComponent"):
            images.append(img.get('name'))
            for param in img:
                if param.get('name') == 'stopVal':
                    image_duration = param.get('val')
        
        results["psyexp_structure"]["image_components"] = images
        results["psyexp_structure"]["duration"] = image_duration
        
        # Check Loop
        loops = []
        for loop in root.findall(".//LoopInitiator"):
            loop_props = {}
            for param in loop:
                if param.get('name') == 'conditionsFile':
                    loop_props['file'] = param.get('val')
            loops.append(loop_props)
        results["psyexp_structure"]["loops"] = loops
        
    except Exception as e:
        results["psyexp_structure"]["error"] = str(e)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/subitizing_result.json
echo "=== Export complete ==="