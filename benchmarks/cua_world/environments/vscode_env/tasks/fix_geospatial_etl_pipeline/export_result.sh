#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Geospatial ETL Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/geospatial_pipeline"
RESULT_FILE="/tmp/geospatial_pipeline_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file
rm -f "$RESULT_FILE"

# Collect all relevant source files into a single JSON dict
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "transforms/coordinate_transform.py": os.path.join(workspace, "transforms", "coordinate_transform.py"),
    "transforms/spatial_operations.py":   os.path.join(workspace, "transforms", "spatial_operations.py"),
    "transforms/area_calculator.py":      os.path.join(workspace, "transforms", "area_calculator.py"),
    "transforms/topology_validator.py":   os.path.join(workspace, "transforms", "topology_validator.py"),
    "exporters/geojson_exporter.py":      os.path.join(workspace, "exporters", "geojson_exporter.py"),
}

result = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[label] = f.read()
    except FileNotFoundError:
        result[label] = None
        print(f"Warning: {path} not found")
    except Exception as e:
        result[label] = None
        print(f"Warning: error reading {path}: {e}")

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported {len([v for v in result.values() if v is not None])} files to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="
ls -la "$RESULT_FILE" 2>/dev/null || echo "Warning: result file not created"
