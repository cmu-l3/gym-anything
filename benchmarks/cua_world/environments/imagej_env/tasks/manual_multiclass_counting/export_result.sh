#!/bin/bash
# Export script for manual_multiclass_counting task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Manual Multi-Class Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Run Python script to analyze the CSV against the ground truth image
# We use Python here (in the env) because we have access to the file system and libraries
python3 << 'PYEOF'
import json
import csv
import os
import math
import numpy as np
from skimage import data, filters, measure, morphology, io

# Configuration
result_csv_path = "/home/ga/ImageJ_Data/results/manual_counts.csv"
task_start_file = "/tmp/task_start_timestamp"
output_json_path = "/tmp/manual_multiclass_result.json"

output = {
    "file_exists": False,
    "file_valid": False,
    "row_count": 0,
    "class_counts": {},
    "class_separation_score": 0.0,
    "points_on_objects": 0,
    "total_points": 0,
    "class_circularity_stats": {},
    "distinct_counters_used": 0,
    "error": None
}

try:
    # 1. Check file existence
    if os.path.exists(result_csv_path):
        output["file_exists"] = True
        
        # Check timestamp
        try:
            start_time = int(open(task_start_file).read().strip())
            mod_time = int(os.path.getmtime(result_csv_path))
            if mod_time < start_time:
                output["error"] = "File predates task start"
        except:
            pass
            
        # 2. Parse CSV
        points = []
        try:
            with open(result_csv_path, 'r') as f:
                # Handle ImageJ results which might be tab or comma separated
                content = f.read()
                dialect = 'excel'
                if '\t' in content:
                    dialect = 'excel-tab'
                
                f.seek(0)
                reader = csv.DictReader(f, dialect=dialect)
                headers = reader.fieldnames
                
                # Identify columns
                x_col = next((h for h in headers if h.lower() in ['x', 'bx', 'x (px)']), None)
                y_col = next((h for h in headers if h.lower() in ['y', 'by', 'y (px)']), None)
                # Counter column: ImageJ often uses 'Counter', 'Type', 'Slice' (if abused for class), or 'Category'
                # Standard Multi-point tool output often has "Counter" column
                class_col = next((h for h in headers if h.lower() in ['counter', 'type', 'ch', 'slice', 'category', 'class']), None)
                
                for row in reader:
                    if x_col and y_col:
                        try:
                            pt = {
                                'x': float(row[x_col]), 
                                'y': float(row[y_col]),
                                'cls': row[class_col] if class_col else "0"
                            }
                            points.append(pt)
                        except ValueError:
                            continue
                            
            output["row_count"] = len(points)
            output["file_valid"] = len(points) > 0
            output["total_points"] = len(points)
            
            # Count classes
            classes = set(p['cls'] for p in points)
            output["distinct_counters_used"] = len(classes)
            for c in classes:
                output["class_counts"][str(c)] = sum(1 for p in points if p['cls'] == c)
                
        except Exception as e:
            output["error"] = f"CSV Parse Error: {e}"

        # 3. Validation against Ground Truth Image
        # We need the 'Blobs' image. Since we can't easily screenshot just the image pane,
        # we load the standard sample from skimage if it matches, or generate a proxy.
        # Actually, ImageJ's blobs sample is very specific. 
        # A robust way is to try to load it from the standard location if we set it up,
        # or download it.
        # However, 'skimage.data.binary_blobs' is NOT the ImageJ blobs.
        # Let's check if we can access the built-in sample copy if setup_imagej.sh put it there.
        
        blobs_path = "/home/ga/ImageJ_Data/raw/blobs.tif"
        img = None
        
        # Try finding the blobs image
        search_paths = [
            "/home/ga/ImageJ_Data/raw/blobs.tif",
            "/home/ga/ImageJ_Data/raw/Blobs.tif",
            "/opt/imagej_samples/blobs.tif",
            "/opt/imagej_samples/Blobs.tif"
        ]
        
        for p in search_paths:
            if os.path.exists(p):
                img = io.imread(p)
                break
        
        # If we can't find the file (because it's built-in to jar), we can't do geometric validation easily.
        # BUT, the task setup instructions in this environment usually put samples in ~/ImageJ_Data/raw.
        # Let's assume for this specific task generation that we might fail to find it and fallback.
        
        if img is not None:
            # Normalize image
            if img.ndim == 3: img = img[:,:,0] # Convert to gray if RGB
            
            # Threshold and label
            thresh = filters.threshold_otsu(img)
            binary = img > thresh # blobs are light on dark usually in this sample? 
            # Actually ImageJ blobs are dark on light in the original, but often inverted.
            # Let's check corner pixel. If corner is light, background is light.
            if img[0,0] > thresh:
                binary = img < thresh # Objects are dark
            else:
                binary = img > thresh # Objects are light
                
            label_image = measure.label(binary)
            props = measure.regionprops(label_image)
            
            # Map points to objects
            # ImageJ coordinates are (X, Y) where X is column, Y is row.
            
            points_on_valid_objects = 0
            class_circularities = {}
            
            for pt in points:
                r, c = int(round(pt['y'])), int(round(pt['x']))
                
                # Bounds check
                if 0 <= r < label_image.shape[0] and 0 <= c < label_image.shape[1]:
                    lbl = label_image[r, c]
                    if lbl > 0:
                        points_on_valid_objects += 1
                        # Find the prop for this label
                        # regionprops list index is usually label-1, but safer to search or map
                        obj = next((x for x in props if x.label == lbl), None)
                        if obj:
                            # Calculate circularity: 4 * pi * Area / Perimeter^2
                            # skimage gives area and perimeter
                            if obj.perimeter > 0:
                                circ = (4 * math.pi * obj.area) / (obj.perimeter ** 2)
                            else:
                                circ = 1.0
                                
                            cls_key = str(pt['cls'])
                            if cls_key not in class_circularities:
                                class_circularities[cls_key] = []
                            class_circularities[cls_key].append(circ)
            
            output["points_on_objects"] = points_on_valid_objects
            
            # Calculate stats per class
            for cls, vals in class_circularities.items():
                if vals:
                    output["class_circularity_stats"][cls] = {
                        "mean": float(np.mean(vals)),
                        "std": float(np.std(vals)),
                        "count": len(vals)
                    }

else:
    output["error"] = "Result file not found"

except Exception as e:
    output["error"] = str(e)

with open(output_json_path, 'w') as f:
    json.dump(output, f, indent=2)
PYEOF

echo "Export complete. Result JSON generated at /tmp/manual_multiclass_result.json"