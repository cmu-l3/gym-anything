#!/bin/bash
# export_result.sh - Post-task hook for high_res_asset_curation
set -e

echo "=== Exporting High-Res Asset Curation Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python script to analyze the downloaded assets
# We use Python because it handles image metadata/resolution checking reliably
python3 << 'PYEOF'
import json
import os
import hashlib
import time
from PIL import Image

# Configuration
TARGET_DIR = "/home/ga/Documents/LectureAssets"
MIN_WIDTH = 2500
REQUIRED_FILES = ["asset_01", "asset_02", "asset_03"]
CREDITS_FILE = "credits.txt"
TASK_START_TIME = 0

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "directory_exists": False,
    "credits_exists": False,
    "credits_content_length": 0,
    "assets": {},
    "unique_images": True,
    "timestamp_valid": True
}

if os.path.exists(TARGET_DIR):
    result["directory_exists"] = True
    
    # Check credits file
    credits_path = os.path.join(TARGET_DIR, CREDITS_FILE)
    if os.path.exists(credits_path):
        result["credits_exists"] = True
        try:
            with open(credits_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read().strip()
                result["credits_content_length"] = len(content)
        except:
            pass

    # Check images
    hashes = set()
    
    for base_name in REQUIRED_FILES:
        asset_info = {
            "exists": False,
            "width": 0,
            "height": 0,
            "format": "unknown",
            "modified_after_start": False,
            "valid_resolution": False
        }
        
        # Look for extensions .jpg, .jpeg, .png
        found_file = None
        for ext in [".jpg", ".jpeg", ".png"]:
            path = os.path.join(TARGET_DIR, base_name + ext)
            if os.path.exists(path):
                found_file = path
                break
        
        if found_file:
            asset_info["exists"] = True
            
            # Check modification time
            mtime = os.path.getmtime(found_file)
            if mtime > TASK_START_TIME:
                asset_info["modified_after_start"] = True
            else:
                result["timestamp_valid"] = False

            # Check image properties
            try:
                with Image.open(found_file) as img:
                    asset_info["width"] = img.width
                    asset_info["height"] = img.height
                    asset_info["format"] = img.format
                    
                    if img.width >= MIN_WIDTH:
                        asset_info["valid_resolution"] = True
                    
                    # Calculate hash for uniqueness check
                    # We hash the pixel data to be robust against metadata changes
                    # Small resize for speed, but keep enough detail
                    img_small = img.resize((100, 100))
                    pixel_hash = hashlib.md5(img_small.tobytes()).hexdigest()
                    if pixel_hash in hashes:
                        result["unique_images"] = False
                    hashes.add(pixel_hash)
            except Exception as e:
                asset_info["error"] = str(e)
        
        result["assets"][base_name] = asset_info

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete. Result saved to /tmp/task_result.json")
PYEOF

# 3. Ensure permissions allow reading the result
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="