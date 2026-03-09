#!/bin/bash
echo "=== Exporting automated_processing_pipeline result ==="

source /workspace/utils/task_utils.sh

take_screenshot /tmp/automated_processing_pipeline_end_screenshot.png

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/automated_processing_pipeline_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'graph_xml_found': False,
    'graph_xml_path': '',
    'graph_has_read': False,
    'graph_has_write': False,
    'graph_has_processing': False,
    'graph_operator_names': [],
    'script_found': False,
    'script_path': '',
    'output_product_found': False,
    'output_product_path': '',
    'output_created_after_start': False,
    'output_band_count': 0,
    'output_band_names': [],
    'output_has_index_band': False
}

# Search for graph XML files
xml_search_dirs = ['/home/ga', '/home/ga/Desktop', '/home/ga/snap_projects', '/tmp']
for d in xml_search_dirs:
    if not os.path.isdir(d):
        continue
    for f in os.listdir(d):
        if not f.lower().endswith('.xml'):
            continue
        full = os.path.join(d, f)
        if 'snap_data' in full or 'workspace' in full:
            continue
        try:
            mtime = int(os.path.getmtime(full))
            if mtime <= task_start:
                continue
            tree = ET.parse(full)
            root = tree.getroot()
            # Check if this is a GPT graph XML (root tag is 'graph')
            if root.tag.lower() == 'graph':
                result['graph_xml_found'] = True
                result['graph_xml_path'] = full
                # Parse graph nodes
                for node in root.findall('.//node') + root.findall('.//Node'):
                    op_el = node.find('operator') or node.find('Operator')
                    if op_el is not None and op_el.text:
                        op_name = op_el.text.strip()
                        result['graph_operator_names'].append(op_name)
                        ol = op_name.lower()
                        if ol == 'read':
                            result['graph_has_read'] = True
                        elif ol == 'write':
                            result['graph_has_write'] = True
                        else:
                            result['graph_has_processing'] = True
                break  # Use first valid graph found
        except Exception:
            continue

# Search for Python/shell scripts that might be the pipeline
for d in xml_search_dirs:
    if not os.path.isdir(d):
        continue
    for f in os.listdir(d):
        fl = f.lower()
        if fl.endswith(('.py', '.sh', '.bash')):
            full = os.path.join(d, f)
            if 'snap_data' in full or 'workspace' in full:
                continue
            try:
                mtime = int(os.path.getmtime(full))
                if mtime > task_start:
                    content = open(full).read().lower()
                    if 'gpt' in content or 'snap' in content or 'snappy' in content:
                        result['script_found'] = True
                        result['script_path'] = full
                        break
            except Exception:
                continue

# Search for output products in snap_projects
output_dirs = ['/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']
for d in output_dirs:
    if not os.path.isdir(d):
        continue
    for root_dir, dirs, files in os.walk(d):
        for f in files:
            if not f.endswith('.dim'):
                continue
            full = os.path.join(root_dir, f)
            if 'snap_data' in full:
                continue
            try:
                mtime = int(os.path.getmtime(full))
                if mtime <= task_start:
                    continue
                result['output_product_found'] = True
                result['output_created_after_start'] = True
                result['output_product_path'] = full

                tree = ET.parse(full)
                xroot = tree.getroot()
                for sbi in xroot.iter('Spectral_Band_Info'):
                    name_el = sbi.find('BAND_NAME')
                    if name_el is not None and name_el.text:
                        bname = name_el.text.strip()
                        result['output_band_names'].append(bname)
                        result['output_band_count'] += 1
                        bl = bname.lower()
                        if any(kw in bl for kw in ['ndvi', 'vegetation', 'index',
                                                    'vi', 'savi', 'evi', 'ratio']):
                            result['output_has_index_band'] = True
            except Exception:
                continue

# Also check for GeoTIFF outputs (agent might write directly to TIFF)
for d in ['/home/ga/snap_projects', '/home/ga/snap_exports', '/home/ga/Desktop']:
    if not os.path.isdir(d):
        continue
    for f in os.listdir(d):
        if f.lower().endswith(('.tif', '.tiff')):
            full = os.path.join(d, f)
            if 'snap_data' in full:
                continue
            try:
                mtime = int(os.path.getmtime(full))
                fsize = os.path.getsize(full)
                if mtime > task_start and fsize > 1024:
                    result['output_product_found'] = True
                    result['output_created_after_start'] = True
            except Exception:
                continue

with open('/tmp/automated_processing_pipeline_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/automated_processing_pipeline_result.json")
PYEOF

echo "=== Export Complete ==="
