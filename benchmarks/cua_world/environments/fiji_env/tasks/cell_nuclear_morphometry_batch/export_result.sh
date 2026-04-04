#!/bin/bash
echo "=== Exporting cell_nuclear_morphometry_batch result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/fiji_morphometry_export.png 2>/dev/null || true

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
echo "Task start timestamp: $TASK_START"

CSV_PATH="/home/ga/Fiji_Data/results/morphometry/nuclear_measurements.csv"
SUMMARY_PATH="/home/ga/Fiji_Data/results/morphometry/batch_summary.txt"
OVERLAY_PATH="/home/ga/Fiji_Data/results/morphometry/qc_overlay.png"
RESULT_JSON="/tmp/morphometry_result.json"

python3 << 'PYEOF'
import json
import os
import sys

task_start = int(open('/tmp/task_start_time').read().strip()) if os.path.exists('/tmp/task_start_time') else 0

csv_path = '/home/ga/Fiji_Data/results/morphometry/nuclear_measurements.csv'
summary_path = '/home/ga/Fiji_Data/results/morphometry/batch_summary.txt'
overlay_path = '/home/ga/Fiji_Data/results/morphometry/qc_overlay.png'
result_json_path = '/tmp/morphometry_result.json'

result = {
    "task_start": task_start,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "total_nuclei": 0,
    "n_images_processed": 0,
    "has_required_columns": False,
    "circularity_all_valid": False,
    "solidity_all_valid": False,
    "area_all_positive": False,
    "summary_exists": False,
    "summary_modified_after_start": False,
    "summary_has_qc_flags": False,
    "summary_size_bytes": 0,
    "overlay_exists": False,
    "overlay_modified_after_start": False,
    "overlay_size_bytes": 0,
    "parse_errors": []
}

# ---- Check nuclear_measurements.csv ----
if os.path.exists(csv_path):
    result["csv_exists"] = True
    csv_mtime = int(os.path.getmtime(csv_path))
    result["csv_modified_after_start"] = csv_mtime > task_start

    try:
        with open(csv_path, 'r', encoding='utf-8-sig') as f:
            lines = [ln.strip() for ln in f.readlines() if ln.strip()]

        if len(lines) >= 2:
            header_raw = lines[0].lower()
            # Normalize header: remove surrounding quotes, split by comma
            header_cols = [c.strip().strip('"').strip("'") for c in header_raw.split(',')]

            # Check for required columns (flexible name matching)
            has_image_col = any(
                kw in col for col in header_cols
                for kw in ('image', 'filename', 'file', 'name', 'label')
            )
            has_nucleus_col = any(
                kw in col for col in header_cols
                for kw in ('nucleus', 'particle', 'cell', 'id', 'label', 'slice')
            )
            has_area_col = any(
                kw in col for col in header_cols
                for kw in ('area',)
            )
            has_circularity_col = any(
                kw in col for col in header_cols
                for kw in ('circ', 'circular', 'round')
            )
            has_solidity_col = any(
                kw in col for col in header_cols
                for kw in ('solid',)
            )

            result["has_required_columns"] = (
                has_area_col and has_circularity_col and has_solidity_col
            )
            result["header_cols"] = header_cols[:15]  # store first 15 for debug

            # Parse data rows
            data_rows = lines[1:]
            result["total_nuclei"] = len(data_rows)

            # Find column indices
            circ_idx = next(
                (i for i, c in enumerate(header_cols) if 'circ' in c or 'circular' in c or 'round' in c),
                None
            )
            solid_idx = next(
                (i for i, c in enumerate(header_cols) if 'solid' in c),
                None
            )
            area_idx = next(
                (i for i, c in enumerate(header_cols) if 'area' in c and 'um' not in c and 'mm' not in c),
                None
            )
            img_idx = next(
                (i for i, c in enumerate(header_cols)
                 if any(kw in c for kw in ('image', 'filename', 'file', 'name', 'label', 'slice'))),
                None
            )

            # Collect unique image filenames
            unique_images = set()
            circ_values = []
            solid_values = []
            area_values = []

            for row_line in data_rows:
                cols = [c.strip().strip('"').strip("'") for c in row_line.split(',')]
                if not any(c for c in cols):
                    continue

                if img_idx is not None and img_idx < len(cols):
                    img_val = cols[img_idx].strip()
                    if img_val and img_val != '0' and img_val.lower() != 'nan':
                        unique_images.add(img_val)

                try:
                    if circ_idx is not None and circ_idx < len(cols):
                        v = float(cols[circ_idx])
                        circ_values.append(v)
                except (ValueError, IndexError):
                    pass

                try:
                    if solid_idx is not None and solid_idx < len(cols):
                        v = float(cols[solid_idx])
                        solid_values.append(v)
                except (ValueError, IndexError):
                    pass

                try:
                    if area_idx is not None and area_idx < len(cols):
                        v = float(cols[area_idx])
                        area_values.append(v)
                except (ValueError, IndexError):
                    pass

            result["n_images_processed"] = len(unique_images)
            result["unique_images_sample"] = list(unique_images)[:5]

            # Validate circularity: all values in (0, 1]
            if circ_values:
                result["circularity_all_valid"] = all(0 < v <= 1.0 for v in circ_values)
                result["circularity_sample"] = circ_values[:5]
                result["circularity_min"] = min(circ_values)
                result["circularity_max"] = max(circ_values)
            else:
                result["circularity_all_valid"] = False

            # Validate solidity: all values in (0, 1]
            if solid_values:
                result["solidity_all_valid"] = all(0 < v <= 1.0 for v in solid_values)
                result["solidity_min"] = min(solid_values)
                result["solidity_max"] = max(solid_values)
            else:
                result["solidity_all_valid"] = False

            # Validate area: all positive
            if area_values:
                result["area_all_positive"] = all(v > 0 for v in area_values)
                result["area_min"] = min(area_values)
                result["area_max"] = max(area_values)
            else:
                result["area_all_positive"] = False

        else:
            result["parse_errors"].append("CSV has fewer than 2 lines (header + data)")

    except Exception as e:
        result["parse_errors"].append(f"CSV parse error: {str(e)}")
        print(f"CSV parse exception: {e}")
else:
    print(f"CSV not found at: {csv_path}")

# ---- Check batch_summary.txt ----
if os.path.exists(summary_path):
    result["summary_exists"] = True
    summary_mtime = int(os.path.getmtime(summary_path))
    result["summary_modified_after_start"] = summary_mtime > task_start
    result["summary_size_bytes"] = os.path.getsize(summary_path)

    try:
        with open(summary_path, 'r', encoding='utf-8-sig') as f:
            summary_content = f.read()
        summary_lower = summary_content.lower()

        # Check for QC flag keywords
        has_pass = 'pass' in summary_lower
        has_fail = 'fail' in summary_lower
        has_n_nuclei = any(kw in summary_lower for kw in ('n_nuclei', 'nuclei', 'count'))
        has_circularity = 'circ' in summary_lower
        has_mean = 'mean' in summary_lower

        result["summary_has_qc_flags"] = has_pass or has_fail
        result["summary_has_n_nuclei"] = has_n_nuclei
        result["summary_has_circularity"] = has_circularity
        result["summary_has_mean"] = has_mean
        result["summary_line_count"] = len([l for l in summary_content.split('\n') if l.strip()])

    except Exception as e:
        result["parse_errors"].append(f"Summary parse error: {str(e)}")
else:
    print(f"Batch summary not found at: {summary_path}")

# ---- Check qc_overlay.png ----
if os.path.exists(overlay_path):
    result["overlay_exists"] = True
    overlay_mtime = int(os.path.getmtime(overlay_path))
    result["overlay_modified_after_start"] = overlay_mtime > task_start
    result["overlay_size_bytes"] = os.path.getsize(overlay_path)
else:
    print(f"QC overlay not found at: {overlay_path}")

# Write result JSON
with open(result_json_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"csv_exists={result['csv_exists']}, "
      f"csv_modified={result['csv_modified_after_start']}, "
      f"total_nuclei={result['total_nuclei']}, "
      f"n_images={result['n_images_processed']}, "
      f"has_req_cols={result['has_required_columns']}, "
      f"circ_valid={result['circularity_all_valid']}, "
      f"solid_valid={result['solidity_all_valid']}, "
      f"area_pos={result['area_all_positive']}, "
      f"summary_exists={result['summary_exists']}, "
      f"summary_qc_flags={result['summary_has_qc_flags']}, "
      f"overlay_exists={result['overlay_exists']}, "
      f"overlay_size={result['overlay_size_bytes']}")

PYEOF

echo "Result JSON written to $RESULT_JSON"
echo ""
echo "=== Export Complete ==="
