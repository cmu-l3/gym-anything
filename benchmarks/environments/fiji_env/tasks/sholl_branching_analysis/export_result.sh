#!/bin/bash
echo "=== Exporting Sholl Analysis Results ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Parse results using Python
# We parse the CSV and TXT files here to create a clean JSON for the verifier.
# This avoids complex bash parsing and ensures we check file validity inside the container.

python3 << EOF
import os
import json
import csv
import re

results_dir = "/home/ga/Fiji_Data/results/sholl"
csv_path = os.path.join(results_dir, "sholl_intersections.csv")
plot_path = os.path.join(results_dir, "sholl_profile.png")
summary_path = os.path.join(results_dir, "sholl_summary.txt")
task_start = int("$TASK_START")

output = {
    "task_start": task_start,
    "task_end": $TASK_END,
    "csv": {"exists": False, "valid": False, "rows": [], "modified_during_task": False},
    "plot": {"exists": False, "size_bytes": 0, "modified_during_task": False},
    "summary": {"exists": False, "data": {}, "modified_during_task": False}
}

# --- Check CSV ---
if os.path.exists(csv_path):
    output["csv"]["exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        output["csv"]["modified_during_task"] = True
    
    try:
        with open(csv_path, 'r') as f:
            # Flexible reading: try to detect headers or assume simple structure
            # Reading first 1kb to sniff structure
            content = f.read()
            f.seek(0)
            
            # Simple parsing strategy: look for numeric pairs
            reader = csv.reader(f)
            data_rows = []
            headers = next(reader, None) # Skip header
            
            for row in reader:
                if len(row) >= 2:
                    try:
                        # Attempt to parse radius and intersections
                        # Handle potential extra columns by taking first two numeric-looking ones
                        nums = []
                        for cell in row:
                            try:
                                nums.append(float(cell))
                            except ValueError:
                                pass
                        if len(nums) >= 2:
                            data_rows.append({"radius": nums[0], "intersections": nums[1]})
                    except Exception:
                        pass
            
            if len(data_rows) > 5:
                output["csv"]["valid"] = True
                output["csv"]["rows"] = data_rows
    except Exception as e:
        output["csv"]["error"] = str(e)

# --- Check Plot ---
if os.path.exists(plot_path):
    output["plot"]["exists"] = True
    size = os.path.getsize(plot_path)
    output["plot"]["size_bytes"] = size
    if os.path.getmtime(plot_path) > task_start:
        output["plot"]["modified_during_task"] = True

# --- Check Summary ---
if os.path.exists(summary_path):
    output["summary"]["exists"] = True
    if os.path.getmtime(summary_path) > task_start:
        output["summary"]["modified_during_task"] = True
    
    try:
        data = {}
        with open(summary_path, 'r') as f:
            for line in f:
                if '=' in line:
                    key, val = line.strip().split('=', 1)
                    try:
                        data[key.strip()] = float(val.strip())
                    except ValueError:
                        data[key.strip()] = val.strip()
        output["summary"]["data"] = data
    except Exception as e:
        output["summary"]["error"] = str(e)

# Save to temporary JSON
with open("/tmp/sholl_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export processed.")
EOF

# 4. Handle permissions for copy_from_env
chmod 644 /tmp/sholl_result.json 2>/dev/null || true

echo "Result JSON generated at /tmp/sholl_result.json"
cat /tmp/sholl_result.json
echo "=== Export complete ==="