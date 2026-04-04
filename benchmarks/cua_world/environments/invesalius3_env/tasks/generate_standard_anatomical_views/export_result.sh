#!/bin/bash
echo "=== Exporting generate_standard_anatomical_views result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to analyze the images
# We use Python because bash is terrible at image processing
python3 << 'PYEOF'
import os
import json
import glob
import math

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

OUTPUT_DIR = "/home/ga/Documents/views"
EXPECTED_FILES = ["anterior.png", "posterior.png", "left.png", "right.png"]
RESULT_FILE = "/tmp/views_analysis.json"

results = {
    "files_found": [],
    "valid_pngs": 0,
    "white_background_count": 0,
    "distinct_images": True,
    "image_hashes": [],
    "error": None,
    "pil_available": PIL_AVAILABLE
}

def is_white(pixel, tolerance=5):
    # Handle RGB and RGBA
    if len(pixel) >= 3:
        r, g, b = pixel[:3]
        return r >= (255 - tolerance) and g >= (255 - tolerance) and b >= (255 - tolerance)
    return False

def get_image_hash(img):
    # Simple perceptual-ish hash: resize to 8x8 and convert to grayscale
    # This helps detect if images are identical or just very similar
    img_s = img.resize((8, 8), Image.Resampling.BILINEAR).convert("L")
    pixels = list(img_s.getdata())
    avg = sum(pixels) / len(pixels)
    bits = "".join("1" if p > avg else "0" for p in pixels)
    return bits

found_images = []

if PIL_AVAILABLE:
    for filename in EXPECTED_FILES:
        path = os.path.join(OUTPUT_DIR, filename)
        file_info = {"name": filename, "exists": False, "valid": False, "white_bg": False}
        
        if os.path.exists(path):
            file_info["exists"] = True
            results["files_found"].append(filename)
            
            try:
                with Image.open(path) as img:
                    img.load() # verify integrity
                    file_info["valid"] = True
                    results["valid_pngs"] += 1
                    
                    # Check background color at corners
                    w, h = img.size
                    corners = [
                        (0, 0), (w-1, 0), (0, h-1), (w-1, h-1)
                    ]
                    
                    # Count how many corners are white
                    white_corners = sum(1 for c in corners if is_white(img.getpixel(c)))
                    
                    # If majority of corners are white, pass
                    if white_corners >= 3:
                        file_info["white_bg"] = True
                        results["white_background_count"] += 1
                    
                    # Store hash for distinctness check
                    img_hash = get_image_hash(img)
                    results["image_hashes"].append(img_hash)
                    
            except Exception as e:
                file_info["error"] = str(e)
        
        found_images.append(file_info)

    # Check distinctness
    hashes = results["image_hashes"]
    if len(hashes) > 1:
        # Check if any two hashes are identical
        if len(set(hashes)) < len(hashes):
            results["distinct_images"] = False
    elif len(hashes) == 0:
        results["distinct_images"] = False
else:
    results["error"] = "PIL not available for verification"
    # Fallback: simple file existence check
    for filename in EXPECTED_FILES:
        if os.path.exists(os.path.join(OUTPUT_DIR, filename)):
            results["files_found"].append(filename)

# Write results
with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

print(json.dumps(results, indent=2))
PYEOF

# Copy result to task_result.json for framework
cp /tmp/views_analysis.json /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="