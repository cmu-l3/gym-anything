#!/bin/bash
# Export script for Particle Solidity Screening task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Results ==="

# Capture final state screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Paths
RESULTS_CSV="/home/ga/ImageJ_Data/results/solidity_measurements.csv"
ROUGHEST_TXT="/home/ga/ImageJ_Data/results/roughest_particle.txt"
TIMESTAMP_FILE="/tmp/task_start_timestamp"

# If Fiji is still open and results exist in window but not file, try to save them
# This helps if the agent did the work but forgot to click "Save As" or messed up the path slightly
if check_results_window; then
    echo "Results window detected. Attempting backup save..."
    SAVE_MACRO="/tmp/backup_save.ijm"
    cat > "$SAVE_MACRO" << 'EOF'
if (isOpen("Results")) {
    selectWindow("Results");
    saveAs("Results", "/tmp/backup_results.csv");
}
EOF
    run_fiji_macro "$(cat $SAVE_MACRO)" 2>/dev/null || true
    
    # If the user file doesn't exist but backup does, we could use backup for "partial credit" logic
    # But for strict compliance, we usually check the expected path. 
    # However, let's verify if the user saved it to the specific path.
fi

# Use Python to parse results and package into JSON
python3 << 'PYEOF'
import json
import csv
import os
import re

csv_path = "/home/ga/ImageJ_Data/results/solidity_measurements.csv"
txt_path = "/home/ga/ImageJ_Data/results/roughest_particle.txt"
start_time_path = "/tmp/task_start_timestamp"

result = {
    "csv_exists": False,
    "txt_exists": False,
    "csv_created_during_task": False,
    "has_solidity_column": False,
    "row_count": 0,
    "min_solidity_in_csv": None,
    "min_solidity_label_in_csv": None,
    "reported_solidity": None,
    "reported_label": None,
    "txt_content": "",
    "timestamp": 0
}

# Check timestamps
try:
    with open(start_time_path, 'r') as f:
        task_start = int(f.read().strip())
        result["timestamp"] = task_start
except:
    task_start = 0

# Analyze CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        result["csv_created_during_task"] = True
        
    try:
        with open(csv_path, 'r') as f:
            # Handle potential ImageJ encoding issues or BOM
            content = f.read()
            
        # Parse CSV
        import io
        reader = csv.DictReader(io.StringIO(content))
        rows = list(reader)
        result["row_count"] = len(rows)
        
        # Check for Solidity column
        # Handle case variations or whitespace
        headers = reader.fieldnames if reader.fieldnames else []
        solidity_col = next((h for h in headers if "solid" in h.lower()), None)
        label_col = next((h for h in headers if "label" in h.lower() or "no." in h.lower()), None)
        
        if solidity_col:
            result["has_solidity_column"] = True
            
            # Find min solidity
            min_val = 1.01
            min_label = None
            
            for row in rows:
                try:
                    val = float(row[solidity_col])
                    if val < min_val:
                        min_val = val
                        if label_col:
                            min_label = row[label_col]
                        else:
                            # Try to infer label from index+1 if not present
                            min_label = str(rows.index(row) + 1)
                except ValueError:
                    continue
            
            if min_val <= 1.0:
                result["min_solidity_in_csv"] = min_val
                result["min_solidity_label_in_csv"] = min_label

    except Exception as e:
        result["csv_error"] = str(e)

# Analyze Text File
if os.path.exists(txt_path):
    result["txt_exists"] = True
    try:
        with open(txt_path, 'r') as f:
            content = f.read().strip()
            result["txt_content"] = content
            
        # Try to extract a number (solidity) from text
        # Look for floating point numbers between 0 and 1
        floats = re.findall(r"0\.\d+", content)
        if floats:
            # Assume the solidity is one of them. Usually there is only one solidity value.
            # If multiple, take the one that looks most like a solidity score (<1)
            result["reported_solidity"] = float(floats[0])
            
        # Try to extract label (integer)
        # Avoid the solidity value itself if it starts with 0
        ints = re.findall(r"\b\d+\b", content)
        if ints:
             # Just take the first integer found as a potential label
             result["reported_label"] = ints[0]
             
    except Exception as e:
        result["txt_error"] = str(e)

# Save result
with open("/tmp/solidity_task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result JSON generated at /tmp/solidity_task_result.json"