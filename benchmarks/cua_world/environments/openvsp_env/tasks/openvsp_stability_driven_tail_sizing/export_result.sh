#!/bin/bash
# Export script for openvsp_stability_driven_tail_sizing task
# Collects file existence, timestamps, tail parameters, polar files, and report content.

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_stability_sizing_result.json"

echo "=== Exporting result for openvsp_stability_driven_tail_sizing ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to flush file handles
kill_openvsp

# Collect results
python3 << 'PYEOF'
import json, os, glob
import xml.etree.ElementTree as ET

models_dir = '/home/ga/Documents/OpenVSP'
desktop    = '/home/ga/Desktop'
model_path    = os.path.join(models_dir, 'stability_restored.vsp3')
baseline_path = os.path.join(models_dir, 'ecrm_unstable.vsp3')
report_path   = os.path.join(desktop, 'stability_report.txt')

# Read task start timestamp
task_start = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    pass


def extract_tail_params(filepath):
    """Extract horizontal tail TotalSpan, chord, and area from vsp3 XML."""
    params = {'span': None, 'root_chord': None, 'tip_chord': None, 'area': None}
    if not os.path.exists(filepath):
        return params
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        for geom in root.iter('Geom'):
            is_tail = False
            for name_el in geom.iter('Name'):
                if name_el.text and name_el.text.strip() == 'Tail':
                    is_tail = True
                    break
            if is_tail:
                # In .vsp3 XML, params are individual tags with Value attr
                for elem in geom.iter():
                    if 'Value' not in elem.attrib:
                        continue
                    try:
                        val = float(elem.get('Value'))
                    except (ValueError, TypeError):
                        continue
                    if elem.tag == 'TotalSpan':
                        params['span'] = val
                    elif elem.tag == 'TotalArea':
                        params['area'] = val
                    elif elem.tag == 'Root_Chord' and val > 1.5:
                        if params['root_chord'] is None or val > params['root_chord']:
                            params['root_chord'] = val
                    elif elem.tag == 'Tip_Chord' and val > 1.5:
                        if params['tip_chord'] is None or val > params['tip_chord']:
                            params['tip_chord'] = val
                break  # only process first Tail component
    except Exception:
        pass
    return params


# Assemble result dict
result = {
    'task_start':     task_start,
    'model_exists':   os.path.isfile(model_path),
    'model_mtime':    int(os.path.getmtime(model_path)) if os.path.isfile(model_path) else 0,
    'model_size':     os.path.getsize(model_path) if os.path.isfile(model_path) else 0,
    'report_exists':  os.path.isfile(report_path),
    'report_content': '',
    'baseline_tail':  extract_tail_params(baseline_path),
    'final_tail':     extract_tail_params(model_path),
    'polar_files':    [],
    'polar_content':  '',
}

# Read report
if result['report_exists']:
    try:
        with open(report_path, 'r', errors='replace') as f:
            result['report_content'] = f.read()[:8000]
    except Exception:
        pass

# Find .polar files created after task start
for dirpath, _dirs, files in os.walk(models_dir):
    for fname in files:
        if fname.endswith('.polar'):
            fpath = os.path.join(dirpath, fname)
            try:
                if os.path.getmtime(fpath) >= task_start:
                    result['polar_files'].append(fpath)
            except Exception:
                pass

# Read latest polar file
if result['polar_files']:
    result['polar_files'].sort(key=lambda p: os.path.getmtime(p), reverse=True)
    try:
        with open(result['polar_files'][0], 'r', errors='replace') as f:
            result['polar_content'] = f.read()[:8000]
    except Exception:
        pass

# Write result JSON
with open('/tmp/openvsp_stability_sizing_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Model: exists={result['model_exists']}, mtime={result['model_mtime']}")
print(f"Baseline tail: {result['baseline_tail']}")
print(f"Final tail:    {result['final_tail']}")
print(f"Report: exists={result['report_exists']}, len={len(result['report_content'])}")
print(f"Polar files:   {len(result['polar_files'])}")
PYEOF

echo "=== Export complete ==="
