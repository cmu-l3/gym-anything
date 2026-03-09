#!/bin/bash
set -e

echo "=== Exporting IVR Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Diagrams/banking_ivr.drawio"
PDF_FILE="/home/ga/Diagrams/exports/banking_ivr.pdf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to parse the .drawio XML content
# We run this inside the container to generate a JSON report
cat > /tmp/analyze_drawio.py << 'EOF'
import sys
import os
import json
import zlib
import base64
from urllib.parse import unquote
import xml.etree.ElementTree as ET

def decode_drawio(content):
    """Decompresses draw.io XML content."""
    try:
        # Check if it's already raw XML
        if content.strip().startswith('<mxGraphModel'):
            return content
        
        # Draw.io usually wraps data in <diagram> tag, base64 encoded, then deflated
        root = ET.fromstring(content)
        diagram = root.find('diagram')
        if diagram is None or not diagram.text:
            return content
            
        # Decode
        compressed = base64.b64decode(diagram.text)
        # Decompress (raw deflate, no header)
        xml_str = zlib.decompress(compressed, -15).decode('utf-8')
        return unquote(xml_str)
    except Exception as e:
        return f"ERROR_DECODING: {str(e)}"

def analyze(file_path):
    result = {
        "file_exists": False,
        "file_size": 0,
        "valid_xml": False,
        "text_content": "",
        "shape_count": 0,
        "edge_count": 0,
        "decision_shapes": 0,
        "keywords_found": []
    }
    
    if not os.path.exists(file_path):
        return result
        
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(file_path)
    
    try:
        with open(file_path, 'r') as f:
            raw_content = f.read()
            
        xml_content = decode_drawio(raw_content)
        
        if "ERROR_DECODING" in xml_content:
            print(f"Warning: {xml_content}", file=sys.stderr)
            # Try parsing raw just in case
            xml_content = raw_content

        # Parse XML
        # Remove namespace prefixes for easier finding if necessary, 
        # but usually ElementTree handles un-namespaced parsing okay with findall(".//tag")
        root = ET.fromstring(xml_content)
        result["valid_xml"] = True
        
        all_text = []
        shapes = 0
        edges = 0
        decisions = 0
        
        # Iterate all cells
        for cell in root.iter('mxCell'):
            # Text is usually in 'value' attribute
            val = cell.get('value', '')
            if val:
                all_text.append(val.lower())
                
            # Count edges
            if cell.get('edge') == '1' or (cell.get('source') and cell.get('target')):
                edges += 1
            # Count vertices/shapes
            elif cell.get('vertex') == '1':
                shapes += 1
                # Check for decision diamond (rhombus)
                style = cell.get('style', '').lower()
                if 'rhombus' in style or 'decision' in style:
                    decisions += 1

        result["text_content"] = " ".join(all_text)
        result["shape_count"] = shapes
        result["edge_count"] = edges
        result["decision_shapes"] = decisions
        
        # Check specific keywords
        targets = ["hours", "closed", "fraud", "balance", "mortgage", "retry", "valid", "10-digit"]
        for t in targets:
            if t in result["text_content"]:
                result["keywords_found"].append(t)
                
    except Exception as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)
        
    return result

if __name__ == "__main__":
    report = analyze(sys.argv[1])
    with open(sys.argv[2], 'w') as f:
        json.dump(report, f)
EOF

# 3. Run analysis
python3 /tmp/analyze_drawio.py "$DRAWIO_FILE" /tmp/analysis.json

# 4. Check PDF export
PDF_EXISTS="false"
if [ -f "$PDF_FILE" ] && [ $(stat -c%s "$PDF_FILE") -gt 1000 ]; then
    PDF_EXISTS="true"
fi

# 5. Check if draw.io is still running
APP_RUNNING="false"
if pgrep -f "drawio" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Combine into final result JSON
# We merge the python analysis with the shell checks
jq -n \
    --slurpfile analysis /tmp/analysis.json \
    --arg pdf_exists "$PDF_EXISTS" \
    --arg app_running "$APP_RUNNING" \
    --arg task_start "$TASK_START" \
    '{
        analysis: $analysis[0],
        pdf_export_exists: ($pdf_exists == "true"),
        app_running: ($app_running == "true"),
        task_start_time: $task_start
    }' > /tmp/task_result.json

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json