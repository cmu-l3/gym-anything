#!/bin/bash
echo "=== Exporting PERT/CPM Construction Schedule Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DRAWIO_PATH="/home/ga/Diagrams/construction_pert.drawio"
PDF_PATH="/home/ga/Diagrams/construction_pert.pdf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze the .drawio XML file and export metrics
# We embed Python here to robustly handle XML parsing and content analysis
python3 << PYEOF > /tmp/analysis_metrics.json
import os
import sys
import json
import re
import zlib
import base64
from urllib.parse import unquote
import xml.etree.ElementTree as ET

result = {
    "file_exists": False,
    "file_modified": False,
    "pdf_exists": False,
    "node_count": 0,
    "edge_count": 0,
    "red_node_count": 0,
    "found_ids": [],
    "has_scheduling_values": False,
    "has_correct_duration": False
}

drawio_path = "$DRAWIO_PATH"
pdf_path = "$PDF_PATH"
task_start = $TASK_START

# Check PDF
if os.path.exists(pdf_path):
    result["pdf_exists"] = True

# Check Drawio file
if os.path.exists(drawio_path):
    result["file_exists"] = True
    if os.path.getmtime(drawio_path) > task_start:
        result["file_modified"] = True
    
    try:
        tree = ET.parse(drawio_path)
        root = tree.getroot()
        
        # Handle compressed draw.io XML (mxfile/diagram/mxGraphModel)
        # Often draw.io saves as compressed XML inside the <diagram> tag
        diagrams = root.findall('diagram')
        xml_content = ""
        
        if diagrams:
            # If compressed
            raw_text = diagrams[0].text
            if raw_text and raw_text.strip():
                try:
                    # Decode: Base64 -> Inflate -> URLDecode (sometimes order varies, usually standard is standard deflate)
                    # Standard draw.io compression: Raw deflate
                    # Actually standard is: Base64 -> Inflate
                    decoded = base64.b64decode(raw_text)
                    xml_content = zlib.decompress(decoded, -15).decode('utf-8')
                    # Parse the inner XML
                    inner_root = ET.fromstring(f"<root>{xml_content}</root>") # Wrap to be safe
                    root = inner_root
                except Exception as e:
                    # Might be uncompressed or different format, fall back to parsing root directly if valid
                    pass

        # Extract all text labels and styles
        all_text = []
        styles = []
        cells = root.findall(".//mxCell")
        
        nodes = 0
        edges = 0
        red_nodes = 0
        
        for cell in cells:
            val = cell.get('value', '')
            style = cell.get('style', '')
            vertex = cell.get('vertex')
            edge = cell.get('edge')
            
            if vertex == '1':
                nodes += 1
                # Check for red coloring (critical path)
                # Look for hex codes for red or 'red' keyword in style
                # Common red hexes: #FF0000, #CC0000, or fill/strokeColor=red
                if 'red' in style.lower() or '#ff0000' in style.lower() or '#cc0000' in style.lower() or 'strokeColor=#B85450' in style: 
                    red_nodes += 1
            
            if edge == '1':
                edges += 1
                
            if val:
                # Remove HTML tags for text analysis
                clean_text = re.sub('<[^<]+?>', ' ', val)
                all_text.append(clean_text)

        result["node_count"] = nodes
        result["edge_count"] = edges
        result["red_node_count"] = red_nodes
        
        combined_text = " ".join(all_text)
        
        # Check for Activity IDs (A through R)
        found_ids = []
        for char in "ABCDEFGHIJKLMNOPQR":
            # Look for the char surrounded by non-word chars or start/end of string
            if re.search(r'\b' + char + r'\b', combined_text):
                found_ids.append(char)
        result["found_ids"] = found_ids
        
        # Check for scheduling terms/values
        # "ES", "EF", "Slack", "Float" or numbers like "61" (project end)
        if "ES" in combined_text or "EF" in combined_text or "Slack" in combined_text or "Float" in combined_text:
            result["has_scheduling_values"] = True
        
        # Check for specific numbers that indicate calculation
        # Project duration is 61
        if "61" in combined_text:
            result["has_correct_duration"] = True
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Merge bash checks and python metrics
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "analysis": $(cat /tmp/analysis_metrics.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="