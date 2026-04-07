#!/bin/bash
# Export script for mitotic_spindle_dynamics task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Mitotic Spindle Dynamics Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os
import csv
import zipfile
import io
import sys

# Try importing image libraries
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

results_dir = "/home/ga/ImageJ_Data/results"
task_start_file = "/tmp/task_start_timestamp"
output_json = "/tmp/mitotic_spindle_dynamics_result.json"

expected_files = {
    "dna_projection": "dna_max_projection.tif",
    "tubulin_projection": "tubulin_max_projection.tif",
    "roi_set": "nuclear_rois.zip",
    "dynamics_csv": "spindle_dynamics.csv",
    "montage": "tubulin_montage.tif"
}

output = {
    "task_start_timestamp": 0,
    "files": {}
}

# Read task start time
try:
    with open(task_start_file, 'r') as f:
        output["task_start_timestamp"] = int(f.read().strip())
except Exception:
    pass

task_start = output["task_start_timestamp"]

# Check each expected file
for key, filename in expected_files.items():
    path = os.path.join(results_dir, filename)
    file_info = {
        "exists": False,
        "size": 0,
        "mtime": 0,
        "valid_time": False
    }

    if os.path.isfile(path):
        file_info["exists"] = True
        file_info["size"] = os.path.getsize(path)
        file_info["mtime"] = int(os.path.getmtime(path))
        file_info["valid_time"] = file_info["mtime"] >= task_start if task_start > 0 else True

        # Analyze TIF images
        if HAS_PIL and filename.endswith('.tif'):
            try:
                img = Image.open(path)
                file_info["width"] = img.size[0]
                file_info["height"] = img.size[1]
                # Count frames in the stack
                n_frames = 1
                try:
                    while True:
                        img.seek(n_frames)
                        n_frames += 1
                except EOFError:
                    pass
                file_info["n_frames"] = n_frames
                file_info["mode"] = img.mode
            except Exception as e:
                file_info["image_error"] = str(e)

        # Analyze ZIP (ROI set)
        if filename.endswith('.zip'):
            try:
                with zipfile.ZipFile(path, 'r') as zf:
                    roi_files = [n for n in zf.namelist() if n.endswith('.roi')]
                    file_info["roi_count"] = len(roi_files)
                    file_info["zip_entries"] = zf.namelist()
            except Exception as e:
                file_info["zip_error"] = str(e)

        # Analyze CSV
        if filename.endswith('.csv'):
            try:
                with open(path, 'r', encoding='utf-8', errors='replace') as f:
                    content = f.read()
                    lines = [l.strip() for l in content.split('\n') if l.strip()]
                    file_info["row_count"] = len(lines) - 1 if len(lines) > 0 else 0  # exclude header

                    # Parse with csv module
                    reader = csv.DictReader(io.StringIO(content))
                    columns = reader.fieldnames or []
                    file_info["columns"] = columns

                    # Check for key columns
                    col_lower = [c.lower() for c in columns]
                    file_info["has_mean_column"] = any('mean' in c for c in col_lower)
                    file_info["has_area_column"] = any('area' in c for c in col_lower)
                    file_info["has_intden_column"] = any('intden' in c or 'rawintden' in c or 'integrated' in c for c in col_lower)

                    # Sample some values from Mean column
                    mean_values = []
                    rows = list(csv.DictReader(io.StringIO(content)))
                    for row in rows:
                        for col_name in columns:
                            if 'mean' in col_name.lower():
                                try:
                                    mean_values.append(float(row[col_name]))
                                except (ValueError, KeyError):
                                    pass
                                break

                    if mean_values:
                        file_info["mean_sample"] = mean_values[:10]
                        file_info["mean_min"] = min(mean_values)
                        file_info["mean_max"] = max(mean_values)
                        file_info["mean_avg"] = sum(mean_values) / len(mean_values)
                        # Check temporal variation
                        file_info["has_variation"] = max(mean_values) != min(mean_values)

            except Exception as e:
                file_info["csv_error"] = str(e)

    output["files"][key] = file_info

with open(output_json, "w") as f:
    json.dump(output, f, indent=2)

print("Export JSON created at", output_json)
PYEOF

echo "=== Export Complete ==="
