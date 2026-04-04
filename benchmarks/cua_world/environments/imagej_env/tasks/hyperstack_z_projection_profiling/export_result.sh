#!/bin/bash
# Export script for Hyperstack Z-Projection task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Hyperstack Task Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define paths
RESULT_TIF="/home/ga/ImageJ_Data/results/chromosomes_timelapse.tif"
RESULT_CSV="/home/ga/ImageJ_Data/results/intensity_trace.csv"
TIMESTAMP_FILE="/tmp/task_start_timestamp"

# Use Python to inspect the output files (TIFF structure and CSV content)
# We do this inside the container to access libraries and avoid copying large files
python3 << 'PYEOF'
import json
import os
import csv
import numpy as np
import sys

# Try importing image libraries
try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

try:
    import skimage.io
    SKIMAGE_AVAILABLE = True
except ImportError:
    SKIMAGE_AVAILABLE = False

result = {
    "tif_exists": False,
    "csv_exists": False,
    "tif_created_during_task": False,
    "csv_created_during_task": False,
    "tif_stats": {
        "width": 0,
        "height": 0,
        "frames": 0,
        "slices": 0,
        "channels": 0,
        "mode": "unknown",
        "is_rgb": False
    },
    "csv_stats": {
        "row_count": 0,
        "has_mean": False,
        "values": []
    },
    "errors": []
}

tif_path = "/home/ga/ImageJ_Data/results/chromosomes_timelapse.tif"
csv_path = "/home/ga/ImageJ_Data/results/intensity_trace.csv"
task_start_path = "/tmp/task_start_timestamp"

# Check timestamps
task_start_time = 0
if os.path.exists(task_start_path):
    try:
        with open(task_start_path, 'r') as f:
            task_start_time = int(f.read().strip())
    except:
        pass

# Analyze TIFF
if os.path.exists(tif_path):
    result["tif_exists"] = True
    if os.path.getmtime(tif_path) > task_start_time:
        result["tif_created_during_task"] = True
    
    try:
        if PIL_AVAILABLE:
            with Image.open(tif_path) as img:
                result["tif_stats"]["width"] = img.width
                result["tif_stats"]["height"] = img.height
                result["tif_stats"]["mode"] = img.mode
                
                # Check for frames/pages
                frames = getattr(img, "n_frames", 1)
                result["tif_stats"]["frames"] = frames
                
                # Determine if RGB (composite) or Grayscale (single channel)
                if img.mode == "RGB":
                    result["tif_stats"]["is_rgb"] = True
                    result["tif_stats"]["channels"] = 3
                elif img.mode == "L" or img.mode == "I;16":
                    result["tif_stats"]["is_rgb"] = False
                    result["tif_stats"]["channels"] = 1
                    
        elif SKIMAGE_AVAILABLE:
            # Fallback to skimage if PIL is missing
            img = skimage.io.imread(tif_path)
            # Shape analysis (heuristic)
            # Usually (Time, Y, X) or (Time, Channels, Y, X)
            shape = img.shape
            result["tif_stats"]["width"] = shape[-1]
            result["tif_stats"]["height"] = shape[-2]
            
            if len(shape) == 3: # (T, Y, X)
                result["tif_stats"]["frames"] = shape[0]
                result["tif_stats"]["channels"] = 1
            elif len(shape) == 4: # (T, C, Y, X) or (C, T, Y, X)
                # This is tricky without metadata, but assuming standard ImageJ
                if shape[-1] == 3: # (Y, X, C)
                    result["tif_stats"]["frames"] = 1
                    result["tif_stats"]["channels"] = 3
                else:
                    result["tif_stats"]["frames"] = shape[0]
                    result["tif_stats"]["channels"] = shape[1]
    except Exception as e:
        result["errors"].append(f"TIFF analysis error: {str(e)}")

# Analyze CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start_time:
        result["csv_created_during_task"] = True
        
    try:
        with open(csv_path, 'r') as f:
            # Handle possible header
            content = f.read().strip()
            lines = content.split('\n')
            
            # Simple check for content
            if len(lines) > 0:
                header = lines[0].lower()
                result["csv_stats"]["has_mean"] = "mean" in header
                
                # Count data rows (exclude header if non-numeric)
                data_rows = []
                for line in lines:
                    # Try to find numbers
                    parts = line.split(',')
                    try:
                        # Find the mean column or just the first number
                        nums = [float(p) for p in parts if p.replace('.','',1).isdigit()]
                        if nums:
                            data_rows.append(nums[0]) # Store first value for debug
                    except:
                        pass
                
                # If header exists, remove it from count
                result["csv_stats"]["row_count"] = len(data_rows)
                result["csv_stats"]["values"] = data_rows[:5] # Sample first 5
                
    except Exception as e:
        result["errors"].append(f"CSV analysis error: {str(e)}")

# Save to JSON
with open("/tmp/hyperstack_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Analysis complete. JSON result saved."