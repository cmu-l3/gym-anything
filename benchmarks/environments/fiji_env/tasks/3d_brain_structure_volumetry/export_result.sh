#!/bin/bash
echo "=== Exporting 3d_brain_structure_volumetry result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/fiji_volumetry_export.png 2>/dev/null || true

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
echo "Task start timestamp: $TASK_START"

CSV_PATH="/home/ga/Fiji_Data/results/volumetry/volume_measurements.csv"
ORTHO_PATH="/home/ga/Fiji_Data/results/volumetry/orthogonal_views.tif"
REPORT_PATH="/home/ga/Fiji_Data/results/volumetry/volumetry_report.txt"
RESULT_JSON="/tmp/volumetry_result.json"

python3 << 'PYEOF'
import json
import os
import sys

task_start = int(open('/tmp/task_start_time').read().strip()) if os.path.exists('/tmp/task_start_time') else 0

csv_path = '/home/ga/Fiji_Data/results/volumetry/volume_measurements.csv'
ortho_path = '/home/ga/Fiji_Data/results/volumetry/orthogonal_views.tif'
report_path = '/home/ga/Fiji_Data/results/volumetry/volumetry_report.txt'
result_json_path = '/tmp/volumetry_result.json'

result = {
    "task_start": task_start,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "n_structures": 0,
    "has_required_columns": False,
    "volumes_mm3": {},
    "all_volumes_positive": False,
    "brain_volume_mm3": 0.0,
    "ventricle_volume_mm3": 0.0,
    "ortho_exists": False,
    "ortho_modified_after_start": False,
    "ortho_size_bytes": 0,
    "report_exists": False,
    "report_modified_after_start": False,
    "report_size_bytes": 0,
    "report_has_brain_keyword": False,
    "report_has_ventricle_keyword": False,
    "parse_errors": []
}

# ---- Check volume_measurements.csv ----
if os.path.exists(csv_path):
    result["csv_exists"] = True
    csv_mtime = int(os.path.getmtime(csv_path))
    result["csv_modified_after_start"] = csv_mtime > task_start

    try:
        with open(csv_path, 'r', encoding='utf-8-sig') as f:
            lines = [ln.strip() for ln in f.readlines() if ln.strip()]

        if len(lines) >= 2:
            header_raw = lines[0].lower()
            header_cols = [c.strip().strip('"').strip("'") for c in header_raw.split(',')]

            # Check required columns
            has_structure_col = any(
                kw in col for col in header_cols
                for kw in ('structure', 'name', 'label', 'region', 'object')
            )
            has_voxel_col = any(
                kw in col for col in header_cols
                for kw in ('voxel', 'count', 'pixel', 'volume_v')
            )
            has_mm3_col = any(
                kw in col for col in header_cols
                for kw in ('mm3', 'mm^3', 'volume_mm', 'vol_mm', 'cubic')
            )
            # Also accept generic 'volume' as mm3 if no explicit unit col
            has_volume_col = has_mm3_col or any('volume' in col for col in header_cols)

            result["has_required_columns"] = has_structure_col and has_volume_col
            result["header_cols"] = header_cols[:15]

            # Find column indices
            struct_idx = next(
                (i for i, c in enumerate(header_cols)
                 if any(kw in c for kw in ('structure', 'name', 'label', 'region', 'object'))),
                None
            )
            mm3_idx = next(
                (i for i, c in enumerate(header_cols)
                 if any(kw in c for kw in ('mm3', 'mm^3', 'volume_mm', 'vol_mm', 'cubic'))),
                None
            )
            # Fallback: first column with 'volume' that isn't 'voxel'
            if mm3_idx is None:
                mm3_idx = next(
                    (i for i, c in enumerate(header_cols)
                     if 'volume' in c and 'voxel' not in c),
                    None
                )
            voxel_idx = next(
                (i for i, c in enumerate(header_cols)
                 if any(kw in c for kw in ('voxel', 'count', 'pixel', 'volume_v'))),
                None
            )

            # Parse data rows
            data_rows = lines[1:]
            result["n_structures"] = len(data_rows)

            volumes_mm3 = {}
            all_volumes = []

            for row_line in data_rows:
                cols = [c.strip().strip('"').strip("'") for c in row_line.split(',')]
                if not any(c for c in cols):
                    continue

                # Get structure name
                struct_name = "unknown"
                if struct_idx is not None and struct_idx < len(cols):
                    struct_name = cols[struct_idx].strip() or "unknown"

                # Get volume in mm3
                vol_mm3 = 0.0
                if mm3_idx is not None and mm3_idx < len(cols):
                    try:
                        vol_mm3 = float(cols[mm3_idx])
                    except (ValueError, IndexError):
                        pass

                volumes_mm3[struct_name] = vol_mm3
                all_volumes.append(vol_mm3)

            result["volumes_mm3"] = volumes_mm3
            result["all_volumes_positive"] = (
                len(all_volumes) > 0 and all(v > 0 for v in all_volumes)
            )

            # Extract brain and ventricle volumes by name matching
            for name, vol in volumes_mm3.items():
                name_lower = name.lower()
                if any(kw in name_lower for kw in ('brain', 'tissue', 'grey', 'gray', 'white', 'matter')):
                    # Take the largest "brain" volume
                    if vol > result["brain_volume_mm3"]:
                        result["brain_volume_mm3"] = vol
                elif any(kw in name_lower for kw in ('ventricle', 'csf', 'vent', 'fluid')):
                    result["ventricle_volume_mm3"] += vol

            # If no structure matched by name, try heuristics
            # (largest volume = brain, smaller = ventricles)
            if result["brain_volume_mm3"] == 0.0 and all_volumes:
                sorted_vols = sorted(all_volumes, reverse=True)
                result["brain_volume_mm3"] = sorted_vols[0]
                if len(sorted_vols) >= 2:
                    result["ventricle_volume_mm3"] = sorted_vols[1]

        else:
            result["parse_errors"].append("CSV has fewer than 2 lines (header + at least 1 data row)")

    except Exception as e:
        result["parse_errors"].append(f"CSV parse error: {str(e)}")
        print(f"CSV parse exception: {e}")
else:
    print(f"CSV not found at: {csv_path}")

# ---- Check orthogonal_views.tif ----
if os.path.exists(ortho_path):
    result["ortho_exists"] = True
    ortho_mtime = int(os.path.getmtime(ortho_path))
    result["ortho_modified_after_start"] = ortho_mtime > task_start
    result["ortho_size_bytes"] = os.path.getsize(ortho_path)
else:
    # Also check for PNG version if agent saved it differently
    alt_ortho = ortho_path.replace('.tif', '.png')
    if os.path.exists(alt_ortho):
        result["ortho_exists"] = True
        ortho_mtime = int(os.path.getmtime(alt_ortho))
        result["ortho_modified_after_start"] = ortho_mtime > task_start
        result["ortho_size_bytes"] = os.path.getsize(alt_ortho)
        result["ortho_path_used"] = alt_ortho
    else:
        print(f"Orthogonal views not found at: {ortho_path}")

# ---- Check volumetry_report.txt ----
if os.path.exists(report_path):
    result["report_exists"] = True
    report_mtime = int(os.path.getmtime(report_path))
    result["report_modified_after_start"] = report_mtime > task_start
    result["report_size_bytes"] = os.path.getsize(report_path)

    try:
        with open(report_path, 'r', encoding='utf-8-sig') as f:
            report_content = f.read()
        report_lower = report_content.lower()

        result["report_has_brain_keyword"] = any(
            kw in report_lower for kw in ('brain', 'tissue', 'cerebral', 'cortex', 'grey', 'gray')
        )
        result["report_has_ventricle_keyword"] = any(
            kw in report_lower for kw in ('ventricle', 'csf', 'cerebrospinal', 'fluid', 'lateral')
        )
        result["report_has_volume_keyword"] = any(
            kw in report_lower for kw in ('volume', 'mm3', 'mm^3', 'voxel', 'cubic')
        )
        result["report_line_count"] = len([l for l in report_content.split('\n') if l.strip()])

    except Exception as e:
        result["parse_errors"].append(f"Report parse error: {str(e)}")
else:
    print(f"Volumetry report not found at: {report_path}")

# Write result JSON
with open(result_json_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"csv_exists={result['csv_exists']}, "
      f"csv_modified={result['csv_modified_after_start']}, "
      f"n_structures={result['n_structures']}, "
      f"has_req_cols={result['has_required_columns']}, "
      f"volumes_mm3={result['volumes_mm3']}, "
      f"all_pos={result['all_volumes_positive']}, "
      f"brain_mm3={result['brain_volume_mm3']:.1f}, "
      f"ventricle_mm3={result['ventricle_volume_mm3']:.1f}, "
      f"ortho_exists={result['ortho_exists']}, "
      f"ortho_size={result['ortho_size_bytes']}, "
      f"report_exists={result['report_exists']}, "
      f"report_brain={result['report_has_brain_keyword']}, "
      f"report_ventricle={result['report_has_ventricle_keyword']}")

PYEOF

echo "Result JSON written to $RESULT_JSON"
echo ""
echo "=== Export Complete ==="
