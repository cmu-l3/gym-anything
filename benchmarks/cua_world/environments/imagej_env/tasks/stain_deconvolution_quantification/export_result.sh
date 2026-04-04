#!/bin/bash
# Export script for stain_deconvolution_quantification task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Stain Deconvolution Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

RESULT_FILE="/home/ga/ImageJ_Data/results/stain_separation_results.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# Python script to parse CSV and export JSON for verifier
python3 << 'PYEOF'
import json
import csv
import os
import io
import re

result_file = "/home/ga/ImageJ_Data/results/stain_separation_results.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "has_dab_keyword": False,
    "has_hematoxylin_keyword": False,
    "dab_area": 0.0,
    "dab_fraction": 0.0,
    "dab_intensity": 0.0,
    "columns": [],
    "raw_content_sample": ""
}

try:
    # Check file metadata
    if os.path.isfile(result_file):
        output["file_exists"] = True
        
        # Check timestamp
        try:
            task_start = int(open(task_start_file).read().strip())
            file_mtime = int(os.path.getmtime(result_file))
            if file_mtime > task_start:
                output["file_created_during_task"] = True
        except:
            pass # Ignore timestamp errors if files missing
            
        # Read content
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        output["raw_content_sample"] = content[:500]
        content_lower = content.lower()
        
        # Keyword checks
        if 'dab' in content_lower or 'brown' in content_lower:
            output["has_dab_keyword"] = True
        if 'hematoxylin' in content_lower or 'blue' in content_lower or 'hema' in content_lower:
            output["has_hematoxylin_keyword"] = True
            
        # Parse CSV
        try:
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)
            output["row_count"] = len(rows)
            output["columns"] = reader.fieldnames or []
            
            # Extract values - try to be flexible with column names
            for row in rows:
                # Convert row to lower case keys for easier matching
                row_lower = {k.lower(): v for k, v in row.items() if k}
                row_str = str(row).lower()
                
                # Identify if this row is for DAB
                is_dab_row = 'dab' in row_str or 'colour_2' in row_str # Standard ImageJ naming often uses Colour_2 for DAB in H DAB vector
                
                # Extract values
                for col, val in row_lower.items():
                    try:
                        val_float = float(val)
                        
                        # Area Fraction
                        if 'fraction' in col or 'percent' in col or '%' in col:
                            if is_dab_row or output["dab_fraction"] == 0:
                                output["dab_fraction"] = val_float
                                
                        # Area
                        elif 'area' in col:
                            if is_dab_row or (output["dab_area"] == 0 and val_float > 100):
                                output["dab_area"] = val_float
                                
                        # Intensity
                        elif 'mean' in col or 'intensity' in col or 'od' in col:
                            if is_dab_row or output["dab_intensity"] == 0:
                                output["dab_intensity"] = val_float
                    except:
                        continue
                        
            # Fallback: if we didn't find specific columns, regex search the raw text for sensible numbers
            if output["dab_fraction"] == 0:
                # Look for numbers between 1 and 99 that might be percentages
                pct_matches = re.findall(r'\b([1-9][0-9]?\.\d+)\b', content)
                if pct_matches:
                    # Take the first plausible percentage
                    output["dab_fraction"] = float(pct_matches[0])

        except Exception as e:
            output["parse_error"] = str(e)

except Exception as e:
    output["error"] = str(e)

# Save JSON
with open("/tmp/stain_deconvolution_quantification_result.json", "w") as f:
    json.dump(output, f, indent=2)
PYEOF

echo "Result JSON generated at /tmp/stain_deconvolution_quantification_result.json"