#!/bin/bash
# Export script for Fractal Venation Analysis task

echo "=== Exporting Fractal Analysis Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Python script to parse results and validate mathematical properties
python3 << 'PYEOF'
import json
import os
import re
import csv
import io

result_file = "/home/ga/ImageJ_Data/results/fractal_venation_results.csv"
task_start_file = "/tmp/task_start_timestamp"
output_json = "/tmp/fractal_venation_analysis_result.json"

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "fractal_dimension": None,
    "box_count_pairs": 0,
    "is_monotonic": False,
    "area_fraction": None,
    "raw_content_sample": "",
    "parse_error": None
}

# 1. Check file existence and timestamp
if os.path.exists(result_file):
    result["file_exists"] = True
    
    try:
        task_start = int(open(task_start_file).read().strip())
        file_mtime = int(os.path.getmtime(result_file))
        if file_mtime > task_start:
            result["file_created_during_task"] = True
    except Exception as e:
        print(f"Timestamp check warning: {e}")

    # 2. Parse Content
    try:
        with open(result_file, 'r', errors='replace') as f:
            content = f.read()
        
        result["raw_content_sample"] = content[:500]
        content_lower = content.lower()

        # Extract Fractal Dimension (D)
        # Look for "D", "Dimension", "Slope", or patterns like "D=1.6"
        d_match = re.search(r'(?:fractal|dimension|slope|d)[\s:=,]+([0-9]+\.?[0-9]*)', content_lower)
        if d_match:
            try:
                result["fractal_dimension"] = float(d_match.group(1))
            except ValueError:
                pass
        
        # If not found via regex, try looking for isolated numbers in plausible range [1.0, 2.0]
        if result["fractal_dimension"] is None:
            nums = re.findall(r'\b([0-9]+\.?[0-9]*)\b', content)
            candidates = [float(n) for n in nums if 1.0 < float(n) < 2.0]
            if candidates:
                # Assuming the D value is one of these (usually the one with most decimals)
                result["fractal_dimension"] = candidates[0]

        # Extract Area Fraction
        # Look for "%Area", "Area Fraction", "Foreground"
        af_match = re.search(r'(?:area|fraction|%|foreground)[\s:=,_]+([0-9]+\.?[0-9]*)', content_lower)
        if af_match:
            try:
                result["area_fraction"] = float(af_match.group(1))
            except ValueError:
                pass

        # Extract Box Count Data for Monotonicity Check
        # Expect lines like: "2, 1050" or "Box Size, Count"
        # We look for pairs of numbers
        lines = content.split('\n')
        box_data = []
        for line in lines:
            nums = re.findall(r'([0-9]+)', line)
            if len(nums) >= 2:
                try:
                    # Usually: Size, Count
                    # Size increases, Count decreases
                    # Or Log(Size), Log(Count)
                    v1 = float(nums[0])
                    v2 = float(nums[1])
                    if v1 > 0 and v2 > 0:
                        box_data.append((v1, v2))
                except ValueError:
                    pass
        
        result["box_count_pairs"] = len(box_data)

        # Check monotonicity: counts should decrease as box size increases
        if len(box_data) >= 3:
            # Sort by first column (box size)
            box_data.sort(key=lambda x: x[0])
            
            # Check if counts (second column) strictly decrease
            # Note: The first column might be "box size" (increasing) or "1/box size" (decreasing)
            # Standard output usually has Box Size (2, 3, 4, 6, 8...)
            
            is_decreasing = all(box_data[i][1] >= box_data[i+1][1] for i in range(len(box_data)-1))
            result["is_monotonic"] = is_decreasing

    except Exception as e:
        result["parse_error"] = str(e)

# Save JSON
with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete. D={result.get('fractal_dimension')}, File={result.get('file_exists')}")
PYEOF

echo "=== Export Complete ==="