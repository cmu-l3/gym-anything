#!/bin/bash
echo "=== Exporting visual_graph_builder_pipeline result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Use a Python script to deeply inspect the SNAP XML and outputs
python3 << 'EOF'
import os
import json
import glob
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'xml_exists': False,
    'xml_parseable': False,
    'has_read': False,
    'has_write': False,
    'has_subset': False,
    'has_bandmaths': False,
    'topology_connected': False,
    'subset_configured': False,
    'bandmaths_configured': False,
    'has_presentation_data': False,
    'dim_exists': False,
    'dim_created_after_start': False,
    'error': None
}

# Load task start timestamp
ts_path = '/tmp/task_start_ts'
if os.path.exists(ts_path):
    with open(ts_path, 'r') as f:
        try:
            result['task_start'] = int(f.read().strip())
        except:
            pass

# Find the XML graph definition
xml_path = "/home/ga/snap_exports/visual_pipeline.xml"
if not os.path.exists(xml_path):
    # Fallback to any XML in the exports directory
    xml_files = glob.glob("/home/ga/snap_exports/*.xml")
    if xml_files:
        xml_path = max(xml_files, key=os.path.getmtime)

if os.path.exists(xml_path):
    result['xml_exists'] = True
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        result['xml_parseable'] = True

        # Extract all operators
        ops = [op.text for op in root.findall('.//node/operator') if op.text]
        result['has_read'] = 'Read' in ops
        result['has_write'] = 'Write' in ops
        result['has_subset'] = 'Subset' in ops
        result['has_bandmaths'] = 'BandMaths' in ops

        # ANTI-GAMING CHECK: Ensure GUI was used (GraphBuilder injects 'Presentation' block)
        if root.find('.//applicationData[@id="Presentation"]') is not None:
            result['has_presentation_data'] = True

        # Topology connection check: Are nodes linked via <sources>?
        sources = root.findall('.//sources/*')
        if len(sources) >= 3:
            result['topology_connected'] = True

        # Parameter configuration checks
        for node in root.findall('.//node'):
            op_el = node.find('operator')
            if op_el is None:
                continue
            op = op_el.text

            if op == 'Subset':
                params = node.find('parameters')
                if params is not None:
                    # Check if region bounds or sourceBands are populated
                    region = params.find('region')
                    bands = params.find('sourceBands')
                    if (region is not None and region.text and region.text.strip()) or \
                       (bands is not None and bands.text and bands.text.strip()):
                        result['subset_configured'] = True

            if op == 'BandMaths':
                params = node.find('parameters')
                if params is not None:
                    # BandMaths requires at least one target band expression
                    expr = params.find('.//expression')
                    if expr is not None and expr.text and expr.text.strip():
                        result['bandmaths_configured'] = True

    except Exception as e:
        result['xml_parseable'] = False
        result['error'] = str(e)

# Find the execution output (.dim)
dim_path = "/home/ga/snap_exports/pipeline_output.dim"
if not os.path.exists(dim_path):
    # Fallback to any dim in exports
    dim_files = glob.glob("/home/ga/snap_exports/*.dim")
    if dim_files:
        dim_path = max(dim_files, key=os.path.getmtime)

if os.path.exists(dim_path):
    result['dim_exists'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime > result['task_start']:
        result['dim_created_after_start'] = True

# Write result state to tmp JSON
with open('/tmp/graph_builder_result.json', 'w') as f:
    json.dump(result, f, indent=2)

EOF

echo "Result JSON saved to /tmp/graph_builder_result.json"
cat /tmp/graph_builder_result.json
echo "=== Export Complete ==="