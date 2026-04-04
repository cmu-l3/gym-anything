#!/bin/bash
set -e

echo "=== Exporting ArchiMate Task Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
DIAGRAM_PATH="/home/ga/Diagrams/claims_architecture.drawio"
PDF_PATH="/home/ga/Diagrams/exports/claims_architecture.pdf"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Python script to analyze the draw.io XML structure
# Draw.io files are often Deflate-compressed XML inside a wrapper.
# We need to decode them to check for specific ArchiMate styles.
cat > /tmp/analyze_diagram.py << 'PYEOF'
import sys
import os
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import json

file_path = sys.argv[1]
task_start = int(sys.argv[2])

result = {
    "file_exists": False,
    "file_valid": False,
    "modified_during_task": False,
    "archimate_library_used": False,
    "elements": {
        "business": [],
        "application": [],
        "technology": []
    },
    "connections_count": 0,
    "styles_found": []
}

if not os.path.exists(file_path):
    print(json.dumps(result))
    sys.exit(0)

result["file_exists"] = True
mtime = os.path.getmtime(file_path)
if mtime > task_start:
    result["modified_during_task"] = True

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    # Content might be compressed in <diagram> tag
    xml_content = None
    diagram = root.find('diagram')
    if diagram is not None and diagram.text:
        try:
            # Decode: Base64 -> Inflate (no header) -> URL Decode
            # Note: draw.io usually does Raw Deflate
            data = base64.b64decode(diagram.text)
            try:
                xml_content = zlib.decompress(data, -15).decode('utf-8')
            except:
                xml_content = zlib.decompress(data).decode('utf-8')
            # Sometimes it's URL encoded first
            xml_content = urllib.parse.unquote(xml_content)
        except Exception as e:
            # Fallback: might be uncompressed
            xml_content = diagram.text
            
    if xml_content:
        # Parse inner XML
        # Wrap in fake root if needed
        try:
            inner_root = ET.fromstring(xml_content)
        except:
            inner_root = ET.fromstring(f"<root>{xml_content}</root>")
        root = inner_root

    result["file_valid"] = True
    
    # Analyze cells
    for cell in root.findall(".//mxCell"):
        style = cell.get("style", "").lower()
        value = cell.get("value", "")
        
        # Check for edges
        if cell.get("edge") == "1":
            result["connections_count"] += 1
            continue
            
        # Check for ArchiMate library usage
        if "archimate3" in style:
            result["archimate_library_used"] = True
            result["styles_found"].append(style)
            
            # Categorize by layer color/type hints in style
            # Business = yellow (#ffff00 or similar), App = blue (#b9e0f7), Tech = green (#d5e8d4)
            # OR by type name in style string e.g. "archimate3.business_actor"
            
            clean_value = value.strip().lower()
            if not clean_value:
                continue

            entry = {"name": value.strip(), "style": style}
            
            if "business" in style or "fillcolor=#ffff" in style:
                result["elements"]["business"].append(entry)
            elif "application" in style or "fillcolor=#b9e0f7" in style:
                result["elements"]["application"].append(entry)
            elif "technology" in style or "device" in style or "fillcolor=#d5e8d4" in style:
                result["elements"]["technology"].append(entry)
            else:
                # Fallback heuristics
                if "actor" in style or "process" in style:
                     result["elements"]["business"].append(entry)
                elif "component" in style or "data_object" in style:
                     result["elements"]["application"].append(entry)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Run analysis
python3 /tmp/analyze_diagram.py "$DIAGRAM_PATH" "$TASK_START" > /tmp/diagram_analysis.json

# 5. Check PDF export
PDF_EXISTS="false"
PDF_SIZE=0
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c%s "$PDF_PATH")
fi

# 6. Combine results
jq -n \
  --slurpfile analysis /tmp/diagram_analysis.json \
  --arg pdf_exists "$PDF_EXISTS" \
  --arg pdf_size "$PDF_SIZE" \
  '{
    diagram_analysis: $analysis[0],
    export: {
      pdf_exists: ($pdf_exists == "true"),
      pdf_size_bytes: ($pdf_size | tonumber)
    }
  }' > /tmp/task_result.json

# 7. Cleanup
rm /tmp/analyze_diagram.py /tmp/diagram_analysis.json

echo "Results exported to /tmp/task_result.json"