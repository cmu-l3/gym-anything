#!/bin/bash
# Do NOT use set -e

echo "=== Exporting stride_threat_model_dfd result ==="

# 1. Capture final state
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/payment_threat_model.drawio"
PNG_FILE="/home/ga/Desktop/payment_threat_model.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# 3. Analyze content with Python
# This handles the XML parsing, decompression (if needed), and content validation
python3 << 'PYEOF' > /tmp/dfd_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/payment_threat_model.drawio"
result = {
    "num_pages": 0,
    "num_shapes": 0,
    "num_edges": 0,
    "num_dashed_containers": 0,
    "components_found": [],
    "stride_keywords_found": [],
    "error": None
}

COMPONENT_KEYWORDS = [
    "browser", "mobile", "gateway", "bank", "web", "api", "auth", 
    "processor", "fraud", "notification", "user", "transaction", "audit"
]

STRIDE_KEYWORDS = [
    "spoofing", "tampering", "repudiation", 
    "information", "disclosure", "denial", "elevation", "privilege"
]

def decompress_diagram(content):
    if not content or not content.strip(): return None
    try:
        # Try raw deflate
        decoded = base64.b64decode(content.strip())
        return ET.fromstring(zlib.decompress(decoded, -15))
    except Exception:
        pass
    try:
        # Try URL decoding
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)
        
        all_cells = []
        for page in pages:
            if page.text:
                xml_content = decompress_diagram(page.text)
                if xml_content:
                    all_cells.extend(list(xml_content.iter('mxCell')))
            # Also check for uncompressed child mxGraphModel
            mxGraph = page.find('mxGraphModel')
            if mxGraph:
                all_cells.extend(list(mxGraph.iter('mxCell')))
                
        # Also check root level if no pages defined (unlikely but possible)
        if not pages:
            all_cells.extend(list(root.iter('mxCell')))

        # Analyze cells
        all_text = []
        for cell in all_cells:
            val = str(cell.get('value') or '').lower()
            style = str(cell.get('style') or '').lower()
            
            # Count shapes vs edges
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                all_text.append(val)
                
                # Check for dashed containers (Trust Boundaries)
                if 'dashed=1' in style:
                    # Check if it's likely a container or boundary
                    if 'container=1' in style or 'swimlane' in style or 'group' in style or 'rectangle' in style:
                        result["num_dashed_containers"] += 1
                        
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                all_text.append(val)

        # Check for keywords in all gathered text
        full_text = " ".join(all_text)
        
        # Check components
        for kw in COMPONENT_KEYWORDS:
            if kw in full_text:
                result["components_found"].append(kw)
                
        # Check STRIDE keywords (mostly expected on page 2, but we check globally)
        for kw in STRIDE_KEYWORDS:
            if kw in full_text:
                result["stride_keywords_found"].append(kw)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Construct final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/dfd_analysis.json || echo "{}")
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="