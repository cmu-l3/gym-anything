#!/bin/bash
# Export script for leaf_skeleton_analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Leaf Skeleton Analysis Result ==="

take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

RESULT_FILE="/home/ga/ImageJ_Data/results/skeleton_analysis.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# Use python to robustly parse the CSV and create a JSON result
python3 << 'PYEOF'
import json, csv, os, io

result_file = "/home/ga/ImageJ_Data/results/skeleton_analysis.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_during_task": False,
    "row_count": 0,
    "columns": [],
    "max_branches": 0,
    "max_junctions": 0,
    "avg_branch_length_detected": False,
    "has_endpoints_data": False,
    "parse_error": None
}

# Check timestamps
try:
    if os.path.exists(task_start_file):
        task_start = int(open(task_start_file).read().strip())
        if os.path.exists(result_file):
            mtime = int(os.path.getmtime(result_file))
            if mtime > task_start:
                output["file_created_during_task"] = True
except Exception as e:
    output["parse_error"] = f"Timestamp check failed: {str(e)}"

if os.path.isfile(result_file):
    output["file_exists"] = True
    output["file_size_bytes"] = os.path.getsize(result_file)
    
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        reader = csv.DictReader(io.StringIO(content))
        rows = list(reader)
        output["row_count"] = len(rows)
        output["columns"] = reader.fieldnames or []
        
        # Check for Analyze Skeleton specific columns
        # Column names can vary slightly by version, usually: 
        # "# Branches", "# Junctions", "Average Branch Length", "# End-point voxels"
        
        branches_keys = [k for k in output["columns"] if "branch" in k.lower() and "#" in k]
        junctions_keys = [k for k in output["columns"] if "junction" in k.lower() and "#" in k]
        length_keys = [k for k in output["columns"] if "average" in k.lower() and "length" in k.lower()]
        endpoints_keys = [k for k in output["columns"] if "end-point" in k.lower()]
        
        if length_keys:
            output["avg_branch_length_detected"] = True
        if endpoints_keys:
            output["has_endpoints_data"] = True
            
        # Extract max values to verify a complex skeleton was found
        # (The main vein network will be the largest skeleton in the list)
        max_branches = 0
        max_junctions = 0
        
        for row in rows:
            # Parse Branches
            for key in branches_keys:
                try:
                    val = int(float(row[key]))
                    if val > max_branches:
                        max_branches = val
                except: pass
            
            # Parse Junctions
            for key in junctions_keys:
                try:
                    val = int(float(row[key]))
                    if val > max_junctions:
                        max_junctions = val
                except: pass
                
        output["max_branches"] = max_branches
        output["max_junctions"] = max_junctions

    except Exception as e:
        output["parse_error"] = f"CSV parse error: {str(e)}"

with open("/tmp/leaf_skeleton_analysis_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export summary: Exists={output['file_exists']}, Created={output['file_created_during_task']}, MaxBranches={output['max_branches']}")
PYEOF

echo "=== Export Complete ==="