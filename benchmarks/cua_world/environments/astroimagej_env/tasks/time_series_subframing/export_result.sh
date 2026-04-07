#!/bin/bash
echo "=== Exporting Time-Series Subframing Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

PROJECT_DIR="/home/ga/AstroImages/time_series"
SUB_DIR="$PROJECT_DIR/subframes"
REPORT_FILE="$PROJECT_DIR/tracking_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to dynamically evaluate ground truth from the agent's files
python3 << PYEOF
import json
import os
import glob
import re
import numpy as np

try:
    from astropy.io import fits
    from scipy import ndimage
    HAS_LIBS = True
except ImportError:
    HAS_LIBS = False

sub_dir = "$SUB_DIR"
report_file = "$REPORT_FILE"
start_time = int("$START_TIME")

result = {
    "report_exists": False,
    "report_content": "",
    "agent_reported": {},
    "subframes_count": 0,
    "files_created_during_task": False,
    "true_dimensions": None,
    "true_centroid_f1": None,
    "true_centroid_f20": None,
    "true_drift": None,
    "has_libs": HAS_LIBS
}

# 1. Parse Agent's Report
if os.path.exists(report_file):
    result["report_exists"] = True
    with open(report_file, 'r') as f:
        content = f.read()
    result["report_content"] = content[:1000]
    
    # Extract values using regex
    patterns = {
        'subframe_width': r'subframe_width:\s*([0-9.]+)',
        'subframe_height': r'subframe_height:\s*([0-9.]+)',
        'star_x_frame1': r'star_x_frame1:\s*([0-9.-]+)',
        'star_y_frame1': r'star_y_frame1:\s*([0-9.-]+)',
        'star_x_frame20': r'star_x_frame20:\s*([0-9.-]+)',
        'star_y_frame20': r'star_y_frame20:\s*([0-9.-]+)',
        'drift_x': r'drift_x:\s*([0-9.-]+)',
        'drift_y': r'drift_y:\s*([0-9.-]+)'
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, content, re.IGNORECASE)
        if match:
            try:
                result["agent_reported"][key] = float(match.group(1))
            except ValueError:
                pass

# 2. Analyze Agent's FITS Output (Dynamic Ground Truth)
fits_files = sorted(glob.glob(os.path.join(sub_dir, "*.fits")) + 
                    glob.glob(os.path.join(sub_dir, "*.fit")))
result["subframes_count"] = len(fits_files)

if fits_files:
    # Check timestamps to ensure anti-gaming (created after task start)
    mtimes = [os.path.getmtime(f) for f in fits_files]
    if any(m > start_time for m in mtimes):
        result["files_created_during_task"] = True

    if HAS_LIBS and len(fits_files) >= 2:
        def get_brightest_star_centroid(filepath):
            try:
                data = fits.getdata(filepath).astype(float)
                # Ensure 2D
                if data.ndim > 2:
                    data = data[0]
                h, w = data.shape
                
                # Find max pixel
                ymax, xmax = np.unravel_index(np.argmax(data), data.shape)
                
                # 21x21 window around max pixel for sub-pixel centroiding
                r = 10
                y1, y2 = max(0, ymax-r), min(h, ymax+r+1)
                x1, x2 = max(0, xmax-r), min(w, xmax+r+1)
                window = data[y1:y2, x1:x2]
                
                bg = np.median(window)
                window_sub = np.maximum(window - bg, 0)
                
                if np.sum(window_sub) > 0:
                    cy_win, cx_win = ndimage.center_of_mass(window_sub)
                    return float(x1 + cx_win), float(y1 + cy_win), w, h
            except Exception:
                pass
            return None, None, 0, 0

        # Process first and last frame
        x1, y1, w1, h1 = get_brightest_star_centroid(fits_files[0])
        x20, y20, w20, h20 = get_brightest_star_centroid(fits_files[-1])
        
        if x1 is not None and x20 is not None:
            result["true_dimensions"] = [w1, h1]
            result["true_centroid_f1"] = [x1, y1]
            result["true_centroid_f20"] = [x20, y20]
            result["true_drift"] = [x20 - x1, y20 - y1]

# Save to temp and move (permission safe)
import tempfile
import shutil
fd, path = tempfile.mkstemp(suffix=".json")
with os.fdopen(fd, 'w') as f:
    json.dump(result, f, indent=2)

os.system(f"sudo cp {path} /tmp/task_result.json")
os.system("sudo chmod 666 /tmp/task_result.json")
os.unlink(path)
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="