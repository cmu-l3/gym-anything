#!/bin/bash
# Export script for openvsp_multi_format_export task
# Records existence and first-line signature of each expected output file

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_multi_format_export_result.json"

echo "=== Exporting result for openvsp_multi_format_export ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP so file handles are released
kill_openvsp

python3 << PYEOF
import json, os

exports_dir = '/home/ga/Documents/OpenVSP/exports'
files = {
    'stl': os.path.join(exports_dir, 'eCRM001_mesh.stl'),
    'tri': os.path.join(exports_dir, 'eCRM001_cart3d.tri'),
    'csv': os.path.join(exports_dir, 'eCRM001_degengeom.csv'),
}

result = {}
for key, path in files.items():
    exists = os.path.isfile(path)
    size = os.path.getsize(path) if exists else 0
    first_bytes = b''
    first_line = ''
    if exists and size > 0:
        with open(path, 'rb') as f:
            first_bytes = f.read(256)
        try:
            first_line = first_bytes.decode('utf-8', errors='replace').splitlines()[0]
        except Exception:
            first_line = ''
    result[key] = {
        'exists': exists,
        'size': size,
        'first_line': first_line,
        'first_bytes_hex': first_bytes[:16].hex() if first_bytes else '',
    }
    print(f"  {key}: exists={exists}, size={size}, first_line={first_line[:60]!r}")

with open('/tmp/openvsp_multi_format_export_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/openvsp_multi_format_export_result.json")
PYEOF

echo "=== Export complete ==="
