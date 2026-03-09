#!/bin/bash
# Export script for Tree Ring Measurement task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Tree Ring Measurement Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths
RESULT_FILE="/home/ga/ImageJ_Data/results/tree_ring_measurements.csv"
TASK_START_FILE="/tmp/task_start_time"

# 3. Use Python to parse the CSV robustly and generate JSON report
python3 << 'PYEOF'
import json
import csv
import os
import re
import statistics

result_file = "/home/ga/ImageJ_Data/results/tree_ring_measurements.csv"
task_start_file = "/tmp/task_start_time"
output_json = "/tmp/tree_ring_measurement_result.json"

result = {
    "file_exists": False,
    "created_during_task": False,
    "row_count": 0,
    "ring_widths": [],
    "valid_widths_count": 0,
    "mean_width": 0.0,
    "width_std_dev": 0.0,
    "has_summary_stats": False,
    "raw_content_preview": "",
    "parse_error": None
}

# Check timestamp
try:
    with open(task_start_file, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

if os.path.exists(result_file):
    result["file_exists"] = True
    mtime = int(os.path.getmtime(result_file))
    if mtime >= task_start:
        result["created_during_task"] = True
    
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            result["raw_content_preview"] = content[:500]
            
            # Check for summary keywords
            content_lower = content.lower()
            if any(k in content_lower for k in ['mean', 'average', 'std', 'min', 'max', 'summary']):
                result["has_summary_stats"] = True

            # Attempt to parse widths
            # Strategy: Extract all numbers, filter for plausible ring widths (e.g., 2-200 pixels)
            # This handles various CSV formats (labeled columns vs simple lists)
            
            # First, try standard CSV parsing if headers exist
            f.seek(0)
            lines = f.readlines()
            result["row_count"] = len(lines)
            
            widths = []
            
            # RegEx to find numbers in lines that might be measurements
            # Look for lines that aren't just headers
            for line in lines:
                # Skip lines that look like pure headers or summary labels
                if re.match(r'^[A-Za-z\s",]+$', line.strip()):
                    continue
                
                # Extract float candidates
                nums = [float(x) for x in re.findall(r'-?\d+\.?\d*', line)]
                
                # Filter candidates: Ring widths should be positive and roughly 2-200px for this image
                # We exclude very large numbers (indices/areas) or very small ones (fractions) if mixed
                valid_nums = [n for n in nums if 2.0 <= n <= 250.0]
                
                if valid_nums:
                    # If multiple valid numbers, assume the one distinct from a counter (1, 2, 3...) is the width
                    # Or just take them all if we aren't sure. 
                    # For simplicity, add all valid width-like numbers found.
                    widths.extend(valid_nums)
            
            result["ring_widths"] = widths
            result["valid_widths_count"] = len(widths)
            
            if widths:
                result["mean_width"] = statistics.mean(widths)
                if len(widths) > 1:
                    result["width_std_dev"] = statistics.stdev(widths)

    except Exception as e:
        result["parse_error"] = str(e)

with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported JSON: Exists={result['file_exists']}, Widths={result['valid_widths_count']}")
PYEOF

# 4. Clean up permissions
chmod 666 /tmp/tree_ring_measurement_result.json 2>/dev/null || true

echo "=== Export Complete ==="