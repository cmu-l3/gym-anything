#!/bin/bash
# Export script for openvsp_vspaero_polar task
# Finds .polar file, captures content; also reads the report

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_vspaero_polar_result.json"

echo "=== Exporting result for openvsp_vspaero_polar ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any open file handles
kill_openvsp

python3 << 'PYEOF'
import json, os, glob

models_dir = '/home/ga/Documents/OpenVSP'
desktop = '/home/ga/Desktop'
report_path = os.path.join(desktop, 'vspaero_report.txt')

# Find .polar file — VSPAero typically writes to same dir as .vsp3 or a subdirectory
polar_paths = []
# Search recursively for .polar files
for root, dirs, files in os.walk(models_dir):
    for fname in files:
        if fname.endswith('.polar'):
            polar_paths.append(os.path.join(root, fname))

# Also check the home directory and common locations
for p in glob.glob(os.path.expanduser('~/Documents/**/*.polar'), recursive=True):
    if p not in polar_paths:
        polar_paths.append(p)

polar_content = ''
polar_exists = False
polar_path_found = ''
polar_data_rows = 0

if polar_paths:
    # Use most recently modified polar file
    polar_paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    polar_path_found = polar_paths[0]
    polar_exists = True
    with open(polar_path_found, 'r', errors='replace') as f:
        polar_content = f.read()
    # Count data rows (non-comment, non-empty lines after header)
    lines = [l.strip() for l in polar_content.splitlines()]
    for i, line in enumerate(lines):
        if line and not line.startswith('#') and not line.startswith('Alpha'):
            # Check if this looks like a data row (starts with a number)
            parts = line.split()
            if parts:
                try:
                    float(parts[0])
                    polar_data_rows += 1
                except ValueError:
                    pass

# Read report
report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'polar_exists': polar_exists,
    'polar_path': polar_path_found,
    'polar_data_rows': polar_data_rows,
    'polar_content': polar_content[:4000],  # first 4KB to keep JSON manageable
    'report_exists': report_exists,
    'report_content': report_content,
}

with open('/tmp/openvsp_vspaero_polar_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Polar: exists={polar_exists}, path={polar_path_found}, data_rows={polar_data_rows}")
print(f"Report: exists={report_exists}, length={len(report_content)}")
PYEOF

echo "=== Export complete ==="
