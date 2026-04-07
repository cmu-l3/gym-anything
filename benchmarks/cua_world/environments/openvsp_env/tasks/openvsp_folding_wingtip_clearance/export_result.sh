#!/bin/bash
set -e
echo "=== Exporting result for openvsp_folding_wingtip_clearance ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file handles before reading XML
kill_openvsp

# Extract validation data directly via Python from inside the container
python3 << 'PYEOF'
import json
import os
import xml.etree.ElementTree as ET

baseline_path = '/home/ga/Documents/OpenVSP/eCRM-001_wing_tail.vsp3'
folded_path = '/home/ga/Documents/OpenVSP/eCRM_folded.vsp3'
report_path = '/home/ga/Desktop/gate_span_report.txt'

def get_wing_info(filepath):
    info = {'exists': False, 'sections': 0, 'outer_dihedral': None, 'mtime': 0}
    if os.path.isfile(filepath):
        info['exists'] = True
        info['mtime'] = int(os.path.getmtime(filepath))
        try:
            tree = ET.parse(filepath)
            root = tree.getroot()
            for geom in root.findall('.//Geom'):
                name_elem = geom.find('.//Name')
                # Find the main wing component
                if name_elem is not None and name_elem.text == 'Wing':
                    sections = geom.findall('.//WingSect')
                    info['sections'] = len(sections)
                    # Get dihedral of the very last section
                    if sections:
                        last_sect = sections[-1]
                        d_elem = last_sect.find('.//Dihedral')
                        if d_elem is not None:
                            info['outer_dihedral'] = float(d_elem.get('Value'))
                    break
        except Exception as e:
            info['error'] = str(e)
    return info

# Parse XML for baseline and modified geometries
base_info = get_wing_info(baseline_path)
fold_info = get_wing_info(folded_path)

report_exists = os.path.isfile(report_path)
report_content = ''
if report_exists:
    with open(report_path, 'r', errors='replace') as f:
        report_content = f.read()

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

result = {
    'task_start': task_start,
    'baseline': base_info,
    'folded': fold_info,
    'report_exists': report_exists,
    'report_content': report_content
}

with open('/tmp/openvsp_folding_wingtip_clearance_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Validation payload generated successfully.")
PYEOF

echo "=== Export complete ==="