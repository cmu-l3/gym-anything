#!/bin/bash
# Export script for texture_region_characterization task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Texture Analysis Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

RESULT_FILE="/home/ga/ImageJ_Data/results/texture_analysis.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# Use Python to robustly parse the CSV and extract metrics
python3 << 'PYEOF'
import json, csv, os, io, sys, statistics

result_file = "/home/ga/ImageJ_Data/results/texture_analysis.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "created_during_task": False,
    "row_count": 0,
    "column_count": 0,
    "headers": [],
    "has_mean": False,
    "has_stddev": False,
    "has_additional": False,
    "mean_values": [],
    "stddev_values": [],
    "stddev_variance": 0.0,
    "task_start_timestamp": 0,
    "parse_error": None
}

# Load task start timestamp
try:
    with open(task_start_file, 'r') as f:
        output["task_start_timestamp"] = int(f.read().strip())
except Exception:
    pass

if os.path.isfile(result_file):
    output["file_exists"] = True
    stats = os.stat(result_file)
    output["file_size_bytes"] = stats.st_size
    
    # Check modification time
    if output["task_start_timestamp"] > 0 and stats.st_mtime > output["task_start_timestamp"]:
        output["created_during_task"] = True
    
    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Parse CSV
        reader = csv.DictReader(io.StringIO(content))
        output["headers"] = reader.fieldnames or []
        output["column_count"] = len(output["headers"])
        rows = list(reader)
        output["row_count"] = len(rows)
        
        # Identify columns loosely
        headers_lower = [h.lower() for h in output["headers"]]
        
        # Check for Mean
        output["has_mean"] = any(x in headers_lower for x in ['mean', 'avg', 'average'])
        
        # Check for StdDev
        output["has_stddev"] = any(x in headers_lower for x in ['std', 'stdev', 'dev', 'sigma'])
        
        # Check for Additional (Min, Max, Mode, Skew, Kurt, Entropy, Circ, etc)
        additional_keywords = ['min', 'max', 'mode', 'skew', 'kurt', 'entropy', 'circ', 'intden', 'median', 'major']
        # Filter out mean and stddev related terms from headers to find "additional"
        remaining_headers = [h for h in headers_lower if not any(x in h for x in ['mean', 'avg', 'std', 'dev', 'label', 'row'])]
        output["has_additional"] = any(any(k in h for k in additional_keywords) for h in remaining_headers)
        
        # Extract numeric values for validation
        mean_vals = []
        stddev_vals = []
        
        for row in rows:
            # Extract Mean
            for k, v in row.items():
                if not k: continue
                kl = k.lower()
                if any(x in kl for x in ['mean', 'avg']) and 'dev' not in kl:
                    try: mean_vals.append(float(v))
                    except: pass
            
            # Extract StdDev
            for k, v in row.items():
                if not k: continue
                kl = k.lower()
                if any(x in kl for x in ['std', 'dev']):
                    try: stddev_vals.append(float(v))
                    except: pass

        output["mean_values"] = mean_vals[:20]
        output["stddev_values"] = stddev_vals[:20]
        
        # Calculate variance of StdDev values (Anti-gaming: different tissues must have different textures)
        if len(stddev_vals) > 1:
            try:
                output["stddev_variance"] = statistics.variance(stddev_vals)
            except:
                output["stddev_variance"] = 0.0
                
    except Exception as e:
        output["parse_error"] = str(e)

with open("/tmp/texture_region_characterization_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export complete. Rows: {output['row_count']}, Created: {output['created_during_task']}")
PYEOF

echo "=== Export Complete ==="