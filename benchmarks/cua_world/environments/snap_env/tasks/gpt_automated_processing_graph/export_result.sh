#!/bin/bash
echo "=== Exporting GPT Automated Processing Graph result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse the XML and check output files using Python
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Initialize result dictionary
result = {
    "xml_exists": False,
    "xml_valid": False,
    "has_read": False,
    "read_file": "",
    "has_bandmaths": False,
    "bandmaths_expression": "",
    "has_write": False,
    "write_file": "",
    "write_format": "",
    "has_node_connections": False,
    "output_tif_exists": False,
    "output_tif_size": 0,
    "output_tif_newer": False,
    "log_exists": False,
    "log_size": 0,
    "parse_error": ""
}

# 1. Parse XML file
xml_path = "/home/ga/snap_exports/band_ratio_graph.xml"
if os.path.exists(xml_path):
    result["xml_exists"] = True
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        if root.tag.lower() == "graph":
            result["xml_valid"] = True
            
            # Check for <sources> tags to indicate node connections
            if len(root.findall(".//sources")) > 0:
                result["has_node_connections"] = True

            for node in root.findall(".//node"):
                op = node.find("operator")
                if op is not None and op.text:
                    op_text = op.text.strip()
                    params = node.find("parameters")
                    
                    if op_text == "Read":
                        result["has_read"] = True
                        if params is not None:
                            f = params.find("file")
                            if f is not None and f.text:
                                result["read_file"] = f.text.strip()
                    
                    elif op_text == "BandMaths":
                        result["has_bandmaths"] = True
                        if params is not None:
                            tbands = params.find("targetBands")
                            if tbands is not None:
                                tband = tbands.find("targetBand")
                                if tband is not None:
                                    expr = tband.find("expression")
                                    if expr is not None and expr.text:
                                        result["bandmaths_expression"] = expr.text.strip()
                    
                    elif op_text == "Write":
                        result["has_write"] = True
                        if params is not None:
                            f = params.find("file")
                            if f is not None and f.text:
                                result["write_file"] = f.text.strip()
                            fmt = params.find("formatName")
                            if fmt is not None and fmt.text:
                                result["write_format"] = fmt.text.strip()
    except Exception as e:
        result["parse_error"] = str(e)

# Get task start time
start_time_file = "/tmp/task_start_time.txt"
start_time = 0
if os.path.exists(start_time_file):
    try:
        start_time = float(open(start_time_file).read().strip())
    except:
        pass

# 2. Check output GeoTIFF
tif_path = "/home/ga/snap_exports/nd_index_output.tif"
if os.path.exists(tif_path):
    result["output_tif_exists"] = True
    result["output_tif_size"] = os.path.getsize(tif_path)
    if os.path.getmtime(tif_path) > start_time:
        result["output_tif_newer"] = True

# 3. Check execution log
log_path = "/home/ga/snap_exports/gpt_execution.log"
if os.path.exists(log_path):
    result["log_exists"] = True
    result["log_size"] = os.path.getsize(log_path)

# Write results
result_path = "/tmp/task_result.json"
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

# Ensure permissions allow reading
os.chmod(result_path, 0o666)

PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="