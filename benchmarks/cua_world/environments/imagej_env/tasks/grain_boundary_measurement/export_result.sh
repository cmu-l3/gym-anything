#!/bin/bash
# Export script for grain_boundary_measurement task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Grain Boundary Measurement Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

RESULT_FILE="/home/ga/ImageJ_Data/results/grain_boundary_analysis.csv"

# Use Python to robustly parse the CSV and validate content
python3 << 'PYEOF'
import json, csv, os, io, sys

result_file = "/home/ga/ImageJ_Data/results/grain_boundary_analysis.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_modified_time": 0,
    "task_start_timestamp": 0,
    "dimensions_found": False,
    "width": 0,
    "height": 0,
    "boundary_length": 0.0,
    "boundary_density": 0.0,
    "parse_error": None
}

# Read task start time
try:
    output["task_start_timestamp"] = int(open(task_start_file).read().strip())
except Exception:
    pass

if os.path.isfile(result_file):
    output["file_exists"] = True
    output["file_modified_time"] = int(os.path.getmtime(result_file))
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        output["file_size_bytes"] = len(content)
        content_lower = content.lower()

        # Simple CSV parsing
        # Supports both "Key,Value" rows OR "Key1,Key2\nVal1,Val2" columns
        
        # Strategy: Look for keywords and associated numbers in the text first
        # This handles unstructured or loosely structured CSVs better
        
        # 1. Look for Width/Height
        import re
        
        # Try to find dimensions
        # Look for typical keywords: Width, Height, w, h, x, y
        # We know the sample is approx 253x255, so we look for numbers in that range (50-2000)
        nums = [float(x) for x in re.findall(r'\b(\d+\.?\d*)\b', content)]
        
        # Filter reasonable dimensions
        potential_dims = [n for n in nums if 50 < n < 2000 and n.is_integer()]
        if len(potential_dims) >= 2:
            output["width"] = potential_dims[0]
            output["height"] = potential_dims[1]
            output["dimensions_found"] = True
        
        # 2. Look for Boundary Length
        # This is usually a large number (e.g. > 100)
        # If it's labeled, even better
        
        lines = content.split('\n')
        for line in lines:
            line_lower = line.lower()
            if any(k in line_lower for k in ['length', 'boundary', 'perim']):
                # Extract number from this line
                line_nums = re.findall(r'(\d+\.?\d*)', line)
                if line_nums:
                    val = float(line_nums[-1]) # Usually value is last
                    if val > 100: # Sanity check for total length vs density
                        output["boundary_length"] = val
        
        # If not found by label, look for largest number in file
        if output["boundary_length"] == 0 and nums:
            large_nums = [n for n in nums if n > 100]
            if large_nums:
                output["boundary_length"] = max(large_nums)

        # 3. Look for Density
        # Should be < 1.0 usually (pixels/pixels^2 or pixels/pixels)
        # AuPbSn boundaries are dense, maybe 0.1 - 0.3 range
        for line in lines:
            line_lower = line.lower()
            if 'density' in line_lower:
                line_nums = re.findall(r'(\d+\.?\d*)', line)
                if line_nums:
                    val = float(line_nums[-1])
                    if val < 1.0:
                        output["boundary_density"] = val
        
        # Fallback for density: Length / (Width * Height)
        if output["boundary_density"] == 0 and output["boundary_length"] > 0 and output["width"] > 0:
             area = output["width"] * output["height"]
             if area > 0:
                 output["boundary_density"] = output["boundary_length"] / area

    except Exception as e:
        output["parse_error"] = str(e)

with open("/tmp/grain_boundary_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export: exists={output['file_exists']}, len={output['boundary_length']}, density={output['boundary_density']}")
PYEOF

echo "=== Export Complete ==="