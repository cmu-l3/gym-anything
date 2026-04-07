#!/bin/bash
# Export script for openvsp_compgeom_wetted_area task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting result for openvsp_compgeom_wetted_area ==="

# Capture final state
take_screenshot /tmp/task_final_screenshot.png

# Terminate OpenVSP so file handles are released
kill_openvsp

python3 << 'PYEOF'
import json, os

exports_dir = '/home/ga/Documents/OpenVSP/exports'
models_dir = '/home/ga/Documents/OpenVSP'
desktop = '/home/ga/Desktop'

report_path = os.path.join(desktop, 'wetted_area_report.txt')
csv_paths = []

# Search for generated CompGeom CSVs in the models directory (OpenVSP default)
for root, dirs, files in os.walk(models_dir):
    for fname in files:
        if ('compgeom' in fname.lower() or 'comp_geom' in fname.lower()) and fname.endswith('.csv'):
            csv_paths.append(os.path.join(root, fname))

# Add the explicitly requested export path if it exists
exports_csv = os.path.join(exports_dir, 'eCRM001_compgeom_results.csv')
if os.path.exists(exports_csv) and exports_csv not in csv_paths:
    csv_paths.append(exports_csv)

csv_exists = False
csv_path = ''
csv_content = ''
csv_mtime = 0

if csv_paths:
    # Use the most recently modified file in case of multiple runs
    csv_paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    csv_path = csv_paths[0]
    csv_exists = True
    csv_mtime = int(os.path.getmtime(csv_path))
    try:
        with open(csv_path, 'r', errors='replace') as f:
            csv_content = f.read()
    except Exception as e:
        print(f"Error reading CSV: {e}")

report_exists = os.path.isfile(report_path)
report_content = ''
report_mtime = 0
if report_exists:
    report_mtime = int(os.path.getmtime(report_path))
    try:
        with open(report_path, 'r', errors='replace') as f:
            report_content = f.read()
    except Exception as e:
        print(f"Error reading report: {e}")

task_start_time = 0
if os.path.exists('/tmp/task_start_timestamp'):
    try:
        with open('/tmp/task_start_timestamp', 'r') as f:
            task_start_time = int(f.read().strip())
    except Exception:
        pass

result = {
    'csv_exists': csv_exists,
    'csv_path': csv_path,
    'csv_mtime': csv_mtime,
    'csv_content': csv_content[:15000],  # Limit size for verifier payload
    'report_exists': report_exists,
    'report_mtime': report_mtime,
    'report_content': report_content,
    'task_start_time': task_start_time
}

with open('/tmp/openvsp_compgeom_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export summary:")
print(f"  CSV exists: {csv_exists} ({csv_path})")
print(f"  Report exists: {report_exists}")
PYEOF

echo "=== Export complete ==="