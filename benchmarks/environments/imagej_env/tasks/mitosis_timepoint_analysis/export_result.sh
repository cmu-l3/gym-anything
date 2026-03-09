#!/bin/bash
# Export script for mitosis_timepoint_analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Mitosis Timepoint Analysis Result ==="

take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import json, csv, os, io, re

result_file = "/home/ga/ImageJ_Data/results/mitosis_timeseries.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "row_count": 0,
    "columns": [],
    "has_frame_column": False,
    "has_area_data": False,
    "has_count_data": False,
    "frame_values": [],
    "area_values": [],
    "count_values": [],
    "distinct_frame_count": 0,
    "area_variation": False,
    "count_variation": False,
    "task_start_timestamp": 0,
    "file_modified_time": 0,
    "parse_error": None
}

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

        output["has_frame_column"] = any(k in content_lower for k in [
            'frame', 'time', 't=', 'timepoint', 'tp', 't1', 't2', 't3'
        ])
        output["has_area_data"] = any(k in content_lower for k in [
            'area', 'total_area', 'thresholded', 'fluor', 'pixels'
        ])
        output["has_count_data"] = any(k in content_lower for k in [
            'count', 'cells', 'objects', 'nuclei', 'number', 'n_'
        ])

        try:
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)
            output["row_count"] = len(rows)
            output["columns"] = reader.fieldnames or []

            frame_vals = []
            area_vals = []
            count_vals = []

            for row in rows:
                for col, val in row.items():
                    col_lower = (col or "").lower()
                    try:
                        n = float(str(val).strip())
                        if any(k in col_lower for k in ['frame', 'time', 't', 'tp', 'index']):
                            frame_vals.append(n)
                        elif any(k in col_lower for k in ['area', 'fluor', 'pixel', 'total']):
                            if n >= 0:
                                area_vals.append(n)
                        elif any(k in col_lower for k in ['count', 'cells', 'object', 'nuclei', 'number', 'n']):
                            if n >= 0:
                                count_vals.append(n)
                    except (ValueError, TypeError):
                        pass

            output["frame_values"] = frame_vals[:10]
            output["area_values"] = area_vals[:10]
            output["count_values"] = count_vals[:10]
            output["distinct_frame_count"] = len(set(frame_vals))

            # If no frame column found, row number implies different timepoints
            if output["distinct_frame_count"] == 0:
                output["distinct_frame_count"] = len(rows)

            # Check variation in area or count values
            if len(area_vals) >= 2:
                output["area_variation"] = max(area_vals) != min(area_vals)
            if len(count_vals) >= 2:
                output["count_variation"] = max(count_vals) != min(count_vals)

        except Exception as e:
            output["parse_error"] = f"CSV parse: {str(e)}"
            lines = [l for l in content.strip().split('\n') if l.strip()]
            output["row_count"] = len(lines)
            output["distinct_frame_count"] = max(0, len(lines) - 1)  # minus header
            nums = re.findall(r'\b(\d+\.?\d*)\b', content)
            all_nums = [float(n) for n in nums if n]
            output["area_values"] = [n for n in all_nums if n > 100][:10]

    except Exception as e:
        output["parse_error"] = str(e)

with open("/tmp/mitosis_timepoint_analysis_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export: file_exists={output['file_exists']}, rows={output['row_count']}, "
      f"distinct_frames={output['distinct_frame_count']}, "
      f"area_variation={output['area_variation']}, count_variation={output['count_variation']}")
PYEOF

echo "=== Export Complete ==="
