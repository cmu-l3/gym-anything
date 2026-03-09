#!/bin/bash
echo "=== Exporting Voronoi Analysis Results ==="

# Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/voronoi"
CSV_PATH="$RESULTS_DIR/territory_measurements.csv"
OVERLAY_PATH="$RESULTS_DIR/voronoi_overlay.png"
SUMMARY_PATH="$RESULTS_DIR/spatial_summary.txt"
EXPORT_JSON="/tmp/voronoi_result.json"
TASK_START_FILE="/tmp/task_start_time"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Read Task Start Time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# 3. Analyze Results using Python
# We perform the heavy lifting here to generate a clean JSON for the verifier
python3 << PYEOF
import json
import os
import csv
import sys

results_dir = "$RESULTS_DIR"
csv_path = "$CSV_PATH"
overlay_path = "$OVERLAY_PATH"
summary_path = "$SUMMARY_PATH"
task_start = int($TASK_START)

output = {
    "csv_exists": False,
    "csv_valid": False,
    "overlay_exists": False,
    "summary_exists": False,
    "file_timestamps_valid": False,
    "row_count": 0,
    "columns_found": [],
    "mean_neighbors": 0.0,
    "mean_area": 0.0,
    "summary_content": {}
}

# Check file existence and timestamps
files_found = 0
files_new = 0

for p in [csv_path, overlay_path, summary_path]:
    if os.path.exists(p):
        files_found += 1
        if os.path.getmtime(p) > task_start:
            files_new += 1

output["csv_exists"] = os.path.exists(csv_path)
output["overlay_exists"] = os.path.exists(overlay_path)
output["summary_exists"] = os.path.exists(summary_path)
output["file_timestamps_valid"] = (files_new == files_found) and (files_found > 0)

# Analyze CSV
if output["csv_exists"]:
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                output["columns_found"] = [c.lower().strip() for c in reader.fieldnames]
            
            rows = list(reader)
            output["row_count"] = len(rows)
            
            # Calculate stats from CSV if possible
            neighbors = []
            areas = []
            
            # Flexible column matching
            neigh_col = next((c for c in output["columns_found"] if "neighbor" in c), None)
            area_col = next((c for c in output["columns_found"] if "area" in c), None)
            
            for row in rows:
                # Handle case-insensitive lookup
                row_lower = {k.lower().strip(): v for k, v in row.items()}
                
                if neigh_col and neigh_col in row_lower:
                    try: neighbors.append(float(row_lower[neigh_col]))
                    except: pass
                
                if area_col and area_col in row_lower:
                    try: areas.append(float(row_lower[area_col]))
                    except: pass
            
            if neighbors:
                output["mean_neighbors"] = sum(neighbors) / len(neighbors)
            if areas:
                output["mean_area"] = sum(areas) / len(areas)
                
            output["csv_valid"] = True
    except Exception as e:
        output["csv_error"] = str(e)

# Analyze Summary Text
if output["summary_exists"]:
    try:
        with open(summary_path, 'r') as f:
            content = f.read()
            output["summary_raw"] = content
            # Try to extract key-values
            for line in content.splitlines():
                if ':' in line:
                    key, val = line.split(':', 1)
                    output["summary_content"][key.strip().lower()] = val.strip()
    except Exception as e:
        output["summary_error"] = str(e)

# Write JSON
with open("$EXPORT_JSON", 'w') as f:
    json.dump(output, f, indent=2)

PYEOF

# 4. Secure result file
chmod 644 "$EXPORT_JSON" 2>/dev/null || true

echo "Result exported to $EXPORT_JSON"
cat "$EXPORT_JSON"
echo "=== Export Complete ==="