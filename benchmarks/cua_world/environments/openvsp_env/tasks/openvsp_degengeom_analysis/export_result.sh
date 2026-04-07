#!/bin/bash
# Export script for openvsp_degengeom_analysis task
# Records DegenGeom CSV status and report content

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_degengeom_analysis_result.json"

echo "=== Exporting result for openvsp_degengeom_analysis ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP
kill_openvsp

python3 << 'PYEOF'
import json, os, glob

exports_dir = '/home/ga/Documents/OpenVSP/exports'
models_dir = '/home/ga/Documents/OpenVSP'
desktop = '/home/ga/Desktop'

csv_path = os.path.join(exports_dir, 'eCRM001_degengeom.csv')
report_path = os.path.join(desktop, 'degengeom_report.txt')

# Check primary CSV location
csv_exists = os.path.isfile(csv_path)
csv_size = os.path.getsize(csv_path) if csv_exists else 0
csv_first_lines = ''

# Also search for any DegenGeom CSV in common locations (agent may save to different path)
alt_csv_paths = []
for root, dirs, files in os.walk(models_dir):
    for fname in files:
        if 'degen' in fname.lower() and fname.endswith('.csv'):
            alt_csv_paths.append(os.path.join(root, fname))

# If primary not found, use most recent alternative
if not csv_exists and alt_csv_paths:
    alt_csv_paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    csv_path = alt_csv_paths[0]
    csv_exists = True
    csv_size = os.path.getsize(csv_path)

if csv_exists:
    with open(csv_path, 'r', errors='replace') as f:
        lines = f.readlines()
    csv_first_lines = ''.join(lines[:20])  # first 20 lines
    csv_row_count = len([l for l in lines if l.strip() and not l.strip().startswith('#')])
else:
    csv_row_count = 0

# Check report
report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

result = {
    'csv_exists': csv_exists,
    'csv_path': csv_path if csv_exists else '',
    'csv_size': csv_size,
    'csv_first_lines': csv_first_lines,
    'csv_row_count': csv_row_count,
    'report_exists': report_exists,
    'report_content': report_content,
}

with open('/tmp/openvsp_degengeom_analysis_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"CSV: exists={csv_exists}, path={csv_path}, size={csv_size}, rows={csv_row_count}")
print(f"Report: exists={report_exists}, length={len(report_content)}")
PYEOF

echo "=== Export complete ==="
