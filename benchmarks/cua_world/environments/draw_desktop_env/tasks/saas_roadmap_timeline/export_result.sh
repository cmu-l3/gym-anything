#!/bin/bash
echo "=== Exporting saas_roadmap_timeline result ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DRAWIO_FILE="/home/ga/Desktop/roadmap.drawio"
PNG_FILE="/home/ga/Desktop/roadmap.png"

# 2. Check File Existence & Timestamps
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false" # Exists but old
        fi
    else
        echo "false"
    fi
}

DRAWIO_CREATED=$(check_file "$DRAWIO_FILE")
PNG_CREATED=$(check_file "$PNG_FILE")

# 3. Python Analysis Script
# This script parses the draw.io XML to verify content structure
python3 << 'PYEOF' > /tmp/roadmap_analysis.json 2>/dev/null
import sys
import os
import zlib
import base64
import json
import re
from urllib.parse import unquote
import xml.etree.ElementTree as ET

def decode_diagram(xml_content):
    """Decompresses draw.io XML content if needed."""
    try:
        # Check for compressed MXFile
        tree = ET.ElementTree(ET.fromstring(xml_content))
        root = tree.getroot()
        if root.tag == 'mxfile':
            diagram = root.find('diagram')
            if diagram is not None and diagram.text:
                data = base64.b64decode(diagram.text)
                xml_content = zlib.decompress(data, -15).decode('utf-8')
                # It might be URL encoded inside the compression
                xml_content = unquote(xml_content)
    except Exception as e:
        pass # Assuming raw XML or failing gracefully
    return xml_content

result = {
    "teams_found": [],
    "quarters_found": [],
    "tasks_found": [],
    "colors_used": [],
    "milestone_found": False,
    "swimlane_structure": False
}

filepath = "/home/ga/Desktop/roadmap.drawio"
if os.path.exists(filepath):
    try:
        with open(filepath, 'r') as f:
            raw_content = f.read()
        
        content = decode_diagram(raw_content)
        # Parse the mxGraphModel
        # Need to handle potential wrapping
        if '<mxGraphModel' not in content:
            # Maybe inside the decoded content, find inner XML
            match = re.search(r'<mxGraphModel.*?</mxGraphModel>', content, re.DOTALL)
            if match:
                content = match.group(0)
        
        try:
            root = ET.fromstring(content)
        except:
            # Fallback for simple wrapping
            root = ET.fromstring(raw_content)

        # Iterate all cells
        cells = root.findall(".//mxCell")
        
        teams = ["frontend", "backend", "mobile"]
        quarters = ["q1", "q2", "q3", "q4"]
        tasks = ["sso", "dashboard", "ios", "api", "android", "dark mode"]
        
        for cell in cells:
            val = (cell.get('value') or "").lower()
            style = (cell.get('style') or "").lower()
            
            # Check Teams (Swimlanes)
            for t in teams:
                if t in val:
                    if "swimlane" in style or int(cell.get('vertex', 0)) == 1:
                        if t not in result["teams_found"]:
                            result["teams_found"].append(t)
            
            # Check Quarters
            for q in quarters:
                if q in val:
                    if q not in result["quarters_found"]:
                        result["quarters_found"].append(q)

            # Check Tasks
            for t in tasks:
                if t in val:
                    task_info = {"name": t, "fill": "none", "parent": cell.get('parent')}
                    
                    # Extract color
                    # fillcolor=#dae8fc (blue), #d5e8d4 (green), #f8cecc (red)
                    fill_match = re.search(r'fillcolor=([^;]+)', style)
                    if fill_match:
                        task_info["fill"] = fill_match.group(1)
                    
                    result["tasks_found"].append(task_info)
                    result["colors_used"].append(task_info["fill"])

            # Check Milestone
            if "launch" in val and ("rhombus" in style or "diamond" in style or int(cell.get('vertex', 0))==1):
                result["milestone_found"] = True

            # Check general structure indicator
            if "swimlane" in style:
                result["swimlane_structure"] = True

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Construct Final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "drawio_created": $DRAWIO_CREATED,
    "png_created": $PNG_CREATED,
    "analysis": $(cat /tmp/roadmap_analysis.json)
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json