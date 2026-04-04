#!/bin/bash
# Export script for gel_band_quantification task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Gel Band Quantification Result ==="

take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import json, csv, os, io, sys, re

result_file = "/home/ga/ImageJ_Data/results/gel_quantification.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "row_count": 0,
    "columns": [],
    "has_lane_data": False,
    "has_intensity_data": False,
    "has_relative_intensity": False,
    "has_position_data": False,
    "lane_values": [],
    "intensity_values": [],
    "relative_values": [],
    "distinct_lanes": 0,
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

        output["has_lane_data"] = any(k in content_lower for k in [
            'lane', 'track', 'column', 'col'
        ])
        output["has_intensity_data"] = any(k in content_lower for k in [
            'intensity', 'density', 'od', 'area', 'intden', 'integrated'
        ])
        output["has_relative_intensity"] = any(k in content_lower for k in [
            'relative', 'percent', 'pct', '%', 'ratio', 'norm', 'fraction'
        ])
        output["has_position_data"] = any(k in content_lower for k in [
            'position', 'pos', 'distance', 'pixel', 'px', 'y', 'location'
        ])

        try:
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)
            output["row_count"] = len(rows)
            output["columns"] = reader.fieldnames or []

            lane_set = set()
            intensity_vals = []
            relative_vals = []

            for row in rows:
                for col, val in row.items():
                    col_lower = (col or "").lower()
                    try:
                        n = float(str(val).strip())
                        if any(k in col_lower for k in ['lane', 'track', 'col']):
                            lane_set.add(str(val).strip())
                            output["lane_values"].append(n)
                        elif any(k in col_lower for k in [
                            'intensity', 'density', 'od', 'intden', 'integrated', 'area'
                        ]):
                            if n > 0:
                                intensity_vals.append(n)
                        elif any(k in col_lower for k in [
                            'relative', 'percent', 'pct', 'norm', 'fraction', 'ratio'
                        ]):
                            relative_vals.append(n)
                    except (ValueError, TypeError):
                        pass

            output["distinct_lanes"] = len(lane_set)
            output["intensity_values"] = intensity_vals[:20]
            output["relative_values"] = relative_vals[:20]

            # If no lane column found, try to infer from repeated position patterns
            if output["distinct_lanes"] == 0 and len(rows) >= 2:
                # Check if there are repeating numeric sequences suggesting multiple lanes
                all_vals = []
                for row in rows:
                    for col, val in row.items():
                        try:
                            all_vals.append(float(str(val).strip()))
                        except Exception:
                            pass
                if all_vals:
                    output["intensity_values"] = [v for v in all_vals if v > 0][:20]

        except Exception as e:
            output["parse_error"] = f"CSV parse: {str(e)}"
            lines = [l for l in content.strip().split('\n') if l.strip()]
            output["row_count"] = len(lines)
            nums = re.findall(r'\b(\d+\.?\d*)\b', content)
            output["intensity_values"] = [float(n) for n in nums[:20] if float(n) > 0]

    except Exception as e:
        output["parse_error"] = str(e)

with open("/tmp/gel_band_quantification_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export: file_exists={output['file_exists']}, rows={output['row_count']}, "
      f"intensity={output['has_intensity_data']}, relative={output['has_relative_intensity']}, "
      f"lanes={output['distinct_lanes']}")
PYEOF

echo "=== Export Complete ==="
