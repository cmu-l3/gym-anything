#!/bin/bash
# Do NOT use set -e

echo "=== Exporting azure_iot_telemetry_pipeline result ==="

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/iot_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/smart_city_iot.drawio"
PNG_FILE="/home/ga/Desktop/smart_city_iot.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
PNG_EXISTS="false"
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

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Python script to analyze the draw.io XML structure
# Checks for Azure shapes and connectivity topology
python3 << 'PYEOF' > /tmp/iot_analysis.json 2>/dev/null || true
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/smart_city_iot.drawio"
result = {
    "azure_shapes_count": 0,
    "components_found": {
        "iot_hub": False,
        "stream_analytics": False,
        "cosmos_db": False,
        "data_lake": False,
        "power_bi": False
    },
    "stream_analytics_out_degree": 0,
    "has_ingestion_flow": False,
    "error": None
}

def decompress_diagram(content):
    """Decompress draw.io content (deflate/base64)."""
    if not content or not content.strip():
        return None
    try:
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
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

        # Extract all cells (handling compression)
        all_cells = []
        pages = root.findall('.//diagram')
        for page in pages:
            inline_cells = list(page.iter('mxCell'))
            if inline_cells:
                all_cells.extend(inline_cells)
            else:
                inner_root = decompress_diagram(page.text or '')
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))
        
        # Fallback for uncompressed
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        # Analysis
        edges = []
        nodes = {} # id -> {style, value}

        for cell in all_cells:
            cid = cell.get('id')
            style = (cell.get('style') or '').lower()
            value = (cell.get('value') or '').lower()
            
            if cell.get('vertex') == '1':
                nodes[cid] = {'style': style, 'value': value}
                
                # Check for Azure shapes
                if 'mxgraph.azure' in style or 'azure' in style:
                    result["azure_shapes_count"] += 1

                # Check specific components (by style OR label)
                # IoT Hub
                if 'iot_hub' in style or 'iothub' in style or 'iot hub' in value:
                    result["components_found"]["iot_hub"] = True
                # Stream Analytics
                if 'stream_analytics' in style or 'stream analytics' in value:
                    result["components_found"]["stream_analytics"] = True
                # Cosmos DB
                if 'cosmos' in style or 'cosmos' in value:
                    result["components_found"]["cosmos_db"] = True
                # Data Lake / Blob
                if 'data_lake' in style or 'blob' in style or 'data lake' in value or 'storage' in value:
                    result["components_found"]["data_lake"] = True
                # Power BI
                if 'power_bi' in style or 'monitor' in style or 'power bi' in value:
                    result["components_found"]["power_bi"] = True

            elif cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                if source and target:
                    edges.append((source, target))

        # Topology Analysis
        # 1. Find the ID of the Stream Analytics node
        sa_ids = []
        for cid, data in nodes.items():
            s = data['style']
            v = data['value']
            if 'stream_analytics' in s or 'stream analytics' in v:
                sa_ids.append(cid)
        
        # 2. Check out-degree of Stream Analytics (Split check)
        for sa_id in sa_ids:
            out_degree = 0
            for src, tgt in edges:
                if src == sa_id:
                    out_degree += 1
            if out_degree > result["stream_analytics_out_degree"]:
                result["stream_analytics_out_degree"] = out_degree

        # 3. Check flow: Hub -> Stream Analytics
        # Find ID of Hub
        hub_ids = []
        for cid, data in nodes.items():
            if 'iot_hub' in data['style'] or 'iothub' in data['style'] or 'iot hub' in data['value']:
                hub_ids.append(cid)
        
        # Check if any edge connects a Hub to a Stream Analytics
        for hub in hub_ids:
            for sa in sa_ids:
                if (hub, sa) in edges:
                    result["has_ingestion_flow"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "png_exists": $PNG_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "analysis": $(cat /tmp/iot_analysis.json)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"