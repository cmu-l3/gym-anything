#!/bin/bash
# Export script for particle_size_distribution task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Particle Size Distribution Result ==="

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Run Python parser to analyze the CSV output
python3 << 'PYEOF'
import json
import csv
import os
import io
import math
import re

result_file = "/home/ga/ImageJ_Data/results/size_distribution.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_after_start": False,
    "individual_row_count": 0,
    "has_area": False,
    "has_perimeter": False,
    "has_diameter": False,
    "has_summary_stats": False,
    "has_bins": False,
    "calculated_stats": {},
    "reported_stats": {},
    "bin_counts": {"small": 0, "medium": 0, "large": 0},
    "mean_diameter_plausible": False
}

try:
    # Check timestamp
    task_start = 0
    if os.path.exists(task_start_file):
        with open(task_start_file) as f:
            task_start = int(f.read().strip())

    if os.path.isfile(result_file):
        output["file_exists"] = True
        output["file_size_bytes"] = os.path.getsize(result_file)
        if os.path.getmtime(result_file) > task_start:
            output["file_created_after_start"] = True

        with open(result_file, 'r', errors='replace') as f:
            content = f.read()
        
        # Heuristic parsing because the file might be mixed format (data + summary)
        lines = [l.strip() for l in content.split('\n') if l.strip()]
        
        # Check for keywords
        content_lower = content.lower()
        output["has_area"] = 'area' in content_lower
        output["has_perimeter"] = 'perimeter' in content_lower
        output["has_diameter"] = any(x in content_lower for x in ['diameter', 'equiv', 'circular'])
        output["has_summary_stats"] = all(x in content_lower for x in ['mean', 'std', 'cv', 'min', 'max'])
        output["has_bins"] = any(x in content_lower for x in ['bin', 'small', 'medium', 'large'])

        # Try to extract individual particle data
        # Assumption: Lines starting with numbers or ID, and containing commas are data
        # We look for a block of numeric data
        data_values = []
        diameters = []
        
        for line in lines:
            # Simple heuristic: line has at least 3 comma-separated numeric values
            parts = line.split(',')
            nums = []
            for p in parts:
                try:
                    nums.append(float(p.strip()))
                except ValueError:
                    pass
            
            if len(nums) >= 3:
                # Potential data row
                data_values.append(nums)
                # Try to identify diameter - usually it's one of the columns
                # If we asked for Area, Perim, Diameter...
                # Area usually > 50, Perim > 20, Diameter > 5
                # Diameter = 2 * sqrt(Area/pi). Let's see if any value matches roughly
                for v in nums:
                    # Rough check for diameter if we assume another column is area
                    # This is tricky without headers, but let's just collect all 'reasonable' diameter-like values
                    if 10 < v < 60: 
                        diameters.append(v)
        
        # Deduplicate rows logic if headers were counted
        if len(data_values) > 5:
            output["individual_row_count"] = len(data_values)
            
            # Verify plausibility of extracted diameters
            # Filter diameters that map to the areas present in the same row
            verified_diameters = []
            for row in data_values:
                # Check for Area/Diameter relationship in this row
                # d = 2 * sqrt(A/pi) => A = pi * (d/2)^2
                row_areas = [x for x in row if x > 50]
                row_diams = [x for x in row if 10 < x < 60]
                
                match_found = False
                for a in row_areas:
                    calc_d = 2 * math.sqrt(a / math.pi)
                    for d in row_diams:
                        if abs(calc_d - d) < 1.0: # Tolerance
                            verified_diameters.append(d)
                            match_found = True
                            break
                    if match_found: break
            
            # If we verified diameters via calculation, use those stats
            if verified_diameters:
                d_mean = sum(verified_diameters) / len(verified_diameters)
                output["calculated_stats"]["mean"] = d_mean
                output["mean_diameter_plausible"] = (15 < d_mean < 45)
            elif diameters:
                # Fallback to all diameter-like values if relationship check failed
                d_mean = sum(diameters) / len(diameters)
                output["calculated_stats"]["mean"] = d_mean
                output["mean_diameter_plausible"] = (15 < d_mean < 45)

        # Extract Reported Summary Stats (looking for key-value pairs)
        # e.g., "Mean, 25.4" or "CV, 28.3"
        for line in lines:
            parts = [p.strip() for p in line.split(',')]
            if len(parts) >= 2:
                key = parts[0].lower()
                try:
                    val = float(parts[1])
                    if 'mean' in key and 'diam' in key: output["reported_stats"]["mean"] = val
                    if 'median' in key: output["reported_stats"]["median"] = val
                    if 'std' in key: output["reported_stats"]["std"] = val
                    if 'cv' in key: output["reported_stats"]["cv"] = val
                    if 'min' in key: output["reported_stats"]["min"] = val
                    if 'max' in key: output["reported_stats"]["max"] = val
                except ValueError:
                    pass

except Exception as e:
    output["error"] = str(e)

with open("/tmp/particle_size_distribution_result.json", "w") as f:
    json.dump(output, f, indent=2)
PYEOF

echo "Export complete."