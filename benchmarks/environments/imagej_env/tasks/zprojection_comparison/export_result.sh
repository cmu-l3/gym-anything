#!/bin/bash
# Export script for Z-Projection Comparison task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Z-Projection Results ==="

# Capture final state
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python to parse CSV and TIFF file to generate a structured JSON result
# We do this here because exec_in_env is not available to the verifier
python3 << 'PYEOF'
import json
import csv
import os
import sys
import re

# Paths
csv_path = "/home/ga/ImageJ_Data/results/zprojection_comparison.csv"
tif_path = "/home/ga/ImageJ_Data/results/stddev_projection.tif"
timestamp_path = "/tmp/task_start_timestamp"

result = {
    "csv_exists": False,
    "csv_valid": False,
    "tif_exists": False,
    "tif_valid": False,
    "projections_found": [],
    "stats": {},
    "tif_dims": [0, 0],
    "tif_stats": {"mean": 0, "max": 0},
    "errors": [],
    "task_start_ts": 0,
    "csv_mtime": 0,
    "tif_mtime": 0
}

# Load task start timestamp
try:
    if os.path.exists(timestamp_path):
        with open(timestamp_path, 'r') as f:
            result["task_start_ts"] = int(f.read().strip())
except Exception as e:
    result["errors"].append(f"Timestamp read error: {e}")

# Check CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
            # Flexible parsing: try standard CSV, then flexible separators
            content = f.read()
            
            # Use csv module with sniffer if possible, or manual parse
            try:
                dialect = csv.Sniffer().sniff(content)
                f.seek(0)
                reader = csv.DictReader(f, dialect=dialect)
            except:
                f.seek(0)
                reader = csv.DictReader(f)
            
            rows = list(reader)
            
            # Normalize headers
            normalized_rows = []
            for row in rows:
                norm_row = {}
                for k, v in row.items():
                    if not k: continue
                    key_lower = k.lower().strip()
                    if 'proj' in key_lower or 'type' in key_lower or 'label' in key_lower:
                        norm_row['type'] = v
                    elif 'mean' in key_lower:
                        norm_row['mean'] = v
                    elif 'std' in key_lower or 'dev' in key_lower:
                        norm_row['std'] = v
                    elif 'min' in key_lower:
                        norm_row['min'] = v
                    elif 'max' in key_lower:
                        norm_row['max'] = v
                normalized_rows.append(norm_row)
            
            # Extract data
            for row in normalized_rows:
                p_type = row.get('type', '').lower()
                
                # Identify projection type
                key = None
                if 'max' in p_type: key = 'max'
                elif 'min' in p_type: key = 'min'
                elif 'avg' in p_type or 'ave' in p_type or 'mean' in p_type: key = 'avg'
                elif 'sum' in p_type: key = 'sum'
                elif 'std' in p_type or 'sd' in p_type: key = 'std'
                
                if key:
                    if key not in result["projections_found"]:
                        result["projections_found"].append(key)
                    
                    try:
                        result["stats"][key] = {
                            "mean": float(row.get('mean', 0)),
                            "std": float(row.get('std', 0)),
                            "min": float(row.get('min', 0)),
                            "max": float(row.get('max', 0))
                        }
                    except ValueError:
                        pass
            
            if len(result["projections_found"]) >= 3:
                result["csv_valid"] = True
                
    except Exception as e:
        result["errors"].append(f"CSV parse error: {e}")

# Check TIF using Python PIL/Pillow if available
if os.path.exists(tif_path):
    result["tif_exists"] = True
    result["tif_mtime"] = int(os.path.getmtime(tif_path))
    
    try:
        from PIL import Image
        import numpy as np
        
        img = Image.open(tif_path)
        result["tif_dims"] = img.size
        
        arr = np.array(img)
        result["tif_stats"]["mean"] = float(np.mean(arr))
        result["tif_stats"]["max"] = float(np.max(arr))
        result["tif_valid"] = True
        
    except ImportError:
        # Fallback if libraries missing (unlikely in this env but safe)
        result["errors"].append("PIL/numpy missing")
        result["tif_valid"] = True # Assume valid if file exists and libraries missing
    except Exception as e:
        result["errors"].append(f"Image read error: {e}")

# Write result
with open("/tmp/zprojection_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="