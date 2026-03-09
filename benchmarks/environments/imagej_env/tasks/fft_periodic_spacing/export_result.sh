#!/bin/bash
# Export script for FFT Periodic Spacing task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting FFT Periodic Spacing Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define Python script to parse results safely
python3 << 'PYEOF'
import json
import csv
import os
import io

results_dir = "/home/ga/ImageJ_Data/results"
fft_image_tif = os.path.join(results_dir, "fft_power_spectrum.tif")
fft_image_png = os.path.join(results_dir, "fft_power_spectrum.png")
report_csv = os.path.join(results_dir, "fft_periodicity_report.csv")
task_start_file = "/tmp/task_start_timestamp"

output = {
    "fft_image_exists": False,
    "fft_image_path": "",
    "fft_image_size_bytes": 0,
    "report_exists": False,
    "report_rows": 0,
    "measured_period": None,
    "image_width_reported": None,
    "task_start_timestamp": 0,
    "files_created_after_start": False
}

# Load task start time
try:
    with open(task_start_file, 'r') as f:
        output["task_start_timestamp"] = int(f.read().strip())
except Exception:
    pass

# Check FFT Image (allow TIF or PNG)
final_fft_path = None
if os.path.isfile(fft_image_tif):
    final_fft_path = fft_image_tif
elif os.path.isfile(fft_image_png):
    final_fft_path = fft_image_png

if final_fft_path:
    output["fft_image_exists"] = True
    output["fft_image_path"] = final_fft_path
    output["fft_image_size_bytes"] = os.path.getsize(final_fft_path)
    
    # Check timestamp
    mtime = int(os.path.getmtime(final_fft_path))
    if output["task_start_timestamp"] > 0 and mtime >= output["task_start_timestamp"]:
        output["files_created_after_start"] = True

# Check Report CSV
if os.path.isfile(report_csv):
    output["report_exists"] = True
    
    # Timestamp check for report as well
    mtime = int(os.path.getmtime(report_csv))
    if output["task_start_timestamp"] > 0 and mtime < output["task_start_timestamp"]:
        output["files_created_after_start"] = False # Fail if report is old

    try:
        with open(report_csv, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
            
        # Try to parse CSV
        reader = csv.DictReader(io.StringIO(content))
        rows = list(reader)
        output["report_rows"] = len(rows)

        # Look for period and width
        for row in rows:
            # Case-insensitive search for keys
            row_lower = {k.lower(): v for k, v in row.items() if k}
            
            # Find period
            for key in ['dominant_period', 'period', 'spacing', 'pore_spacing']:
                if key in row_lower:
                    try:
                        val = float(row_lower[key])
                        if val > 0:
                            output["measured_period"] = val
                    except ValueError:
                        pass
            
            # Find width
            for key in ['image_width', 'width', 'w']:
                if key in row_lower:
                    try:
                        val = float(row_lower[key])
                        if val > 0:
                            output["image_width_reported"] = val
                    except ValueError:
                        pass
                        
        # Fallback: if headers aren't standard, look for numeric values in text
        if output["measured_period"] is None:
             import re
             # Look for numbers in the file content
             nums = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content)]
             # Heuristic: Period is usually small (5-50), Width is larger (150-500)
             candidates_period = [n for n in nums if 5 <= n <= 50]
             candidates_width = [n for n in nums if 100 <= n <= 500]
             
             if candidates_period:
                 output["measured_period"] = candidates_period[0]
             if candidates_width:
                 output["image_width_reported"] = candidates_width[0]

    except Exception as e:
        print(f"Error parsing CSV: {e}")

# Save result JSON
with open("/tmp/fft_task_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "=== Export Complete ==="