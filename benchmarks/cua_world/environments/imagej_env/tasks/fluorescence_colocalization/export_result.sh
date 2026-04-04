#!/bin/bash
# Export script for fluorescence_colocalization task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Fluorescence Colocalization Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

RESULT_FILE="/home/ga/ImageJ_Data/results/colocalization_results.csv"

python3 << 'PYEOF'
import json, csv, os, io, sys

result_file = "/home/ga/ImageJ_Data/results/colocalization_results.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "row_count": 0,
    "columns": [],
    "has_red_data": False,
    "has_green_data": False,
    "has_colocalization_metric": False,
    "has_area_data": False,
    "has_intensity_data": False,
    "colocalization_values": [],
    "area_values": [],
    "intensity_values": [],
    "task_start_timestamp": 0,
    "file_modified_time": 0,
    "parse_error": None
}

# Load task start time
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

        # Check for channel keywords
        output["has_red_data"] = any(k in content_lower for k in [
            'red', 'channel1', 'ch1', 'r.', 'r_', 'rhodamine', 'channel 1', 'chan1'
        ])
        output["has_green_data"] = any(k in content_lower for k in [
            'green', 'channel2', 'ch2', 'g.', 'g_', 'fitc', 'channel 2', 'chan2'
        ])
        output["has_colocalization_metric"] = any(k in content_lower for k in [
            'pearson', 'manders', 'overlap', 'coloc', 'coefficient',
            'correlation', ' m1', ' m2', 'm1,', 'm2,', 'iou', 'jaccard'
        ])
        output["has_area_data"] = any(k in content_lower for k in [
            'area', 'pixels', 'px', 'size'
        ])
        output["has_intensity_data"] = any(k in content_lower for k in [
            'intensity', 'mean', 'integrated', 'rawintden', 'intden'
        ])

        # Try to parse as CSV and extract numeric values
        try:
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)
            output["row_count"] = len(rows)
            output["columns"] = reader.fieldnames or []

            # Extract numeric values from any column
            all_nums = []
            for row in rows:
                for col, val in row.items():
                    try:
                        n = float(str(val).strip())
                        col_lower = col.lower() if col else ""
                        if any(k in col_lower for k in ['area', 'px', 'pixel', 'size']):
                            output["area_values"].append(n)
                        elif any(k in col_lower for k in ['intensity', 'mean', 'intden']):
                            output["intensity_values"].append(n)
                        elif any(k in col_lower for k in [
                            'pearson', 'manders', 'overlap', 'coloc', 'coeff', 'm1', 'm2', 'r'
                        ]):
                            output["colocalization_values"].append(n)
                        all_nums.append(n)
                    except (ValueError, TypeError):
                        pass

            # If we didn't categorize values well, try extracting all positive nums
            if not output["colocalization_values"] and not output["area_values"]:
                # Look for values between 0 and 1 (likely colocalization metrics)
                coloc_candidates = [n for n in all_nums if 0.0 <= n <= 1.0 and n > 0]
                # Look for large positive values (likely areas)
                area_candidates = [n for n in all_nums if n > 100]
                output["colocalization_values"] = coloc_candidates[:10]
                output["area_values"] = area_candidates[:10]

        except Exception as e:
            output["parse_error"] = f"CSV parse error: {str(e)}"
            # Fall back: check raw content for numbers
            import re
            nums = re.findall(r'\b(\d+\.?\d*)\b', content)
            all_nums = [float(n) for n in nums[:100] if n]
            output["row_count"] = len(content.strip().split('\n'))

    except Exception as e:
        output["parse_error"] = str(e)

with open("/tmp/fluorescence_colocalization_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export: file_exists={output['file_exists']}, rows={output['row_count']}, "
      f"red={output['has_red_data']}, green={output['has_green_data']}, "
      f"coloc_metric={output['has_colocalization_metric']}")
PYEOF

echo "=== Export Complete ==="
