#!/bin/bash
# Do NOT use set -e

echo "=== Exporting google_boutique_k8s_architecture result ==="

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/boutique_architecture.drawio"
PNG_FILE="/home/ga/Desktop/boutique_architecture.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# 2. Parse draw.io XML content
# We use Python to parse the XML, handling both compressed (deflate) and uncompressed formats.
python3 << 'PYEOF' > /tmp/boutique_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/boutique_architecture.drawio"
result = {
    "error": None,
    "num_shapes": 0,
    "num_edges": 0,
    "num_pages": 0,
    "found_services": [],
    "found_redis": False,
    "found_ingress": False,
    "found_protocols": [],
    "has_namespace_group": False
}

SERVICE_NAMES = [
    "frontend", "cartservice", "productcatalog", "currencyservice",
    "paymentservice", "shippingservice", "emailservice", "checkoutservice",
    "recommendationservice", "adservice", "loadgenerator"
]

def decompress_diagram(content):
    """Try to decompress draw.io diagram content."""
    if not content or not content.strip():
        return None
    try:
        # Try raw deflate
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Try URL decoded
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Count pages
        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)
        
        all_cells = []
        for page in pages:
            # Check for inline content
            inline = list(page.iter('mxCell'))
            if inline:
                all_cells.extend(inline)
            else:
                # Check for compressed content
                inner = decompress_diagram(page.text or '')
                if inner is not None:
                    all_cells.extend(list(inner.iter('mxCell')))
        
        # Fallback for uncompressed root
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)
        
        all_text = []
        
        for cell in all_cells:
            val = (cell.get('value') or '').lower()
            style = (cell.get('style') or '').lower()
            
            # Skip root/layer cells
            if cell.get('id') in ('0', '1'):
                continue
                
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                all_text.append(val)
                
                # Check for Redis
                if 'redis' in val:
                    result["found_redis"] = True
                
                # Check for Ingress
                if 'ingress' in val or 'gateway' in val or 'internet' in val:
                    result["found_ingress"] = True
                
                # Check for Namespace/Group
                if 'group' in style or 'swimlane' in style or 'container' in style:
                    result["has_namespace_group"] = True
                    
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                all_text.append(val)
        
        # Check found services
        full_text = " ".join(all_text)
        # Clean HTML
        full_text = re.sub(r'<[^>]+>', ' ', full_text)
        
        for svc in SERVICE_NAMES:
            # Simple substring match is usually sufficient for these specific names
            if svc in full_text:
                result["found_services"].append(svc)
                
        # Check protocols
        if 'grpc' in full_text:
            result["found_protocols"].append("grpc")
        if 'http' in full_text:
            result["found_protocols"].append("http")

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/boutique_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"