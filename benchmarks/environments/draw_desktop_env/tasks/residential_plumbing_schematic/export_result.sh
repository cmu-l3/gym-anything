#!/bin/bash
# residential_plumbing_schematic export
set -u

echo "=== Exporting Plumbing Schematic Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DRAWIO="/home/ga/Desktop/plumbing_schematic.drawio"
OUTPUT_PNG="/home/ga/Desktop/plumbing_schematic.png"

# Screenshot final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python analysis script inside the container to parse the drawio XML
# This avoids complex bash XML parsing and handles the graph logic locally
python3 << 'PY_EOF' > /tmp/schematic_analysis.json
import sys
import os
import json
import base64
import zlib
import re
import xml.etree.ElementTree as ET

def decode_drawio(content):
    """Decompress draw.io content if needed."""
    try:
        # Check for standard XML header
        if content.strip().startswith('<?xml'):
            return ET.fromstring(content)
        
        # Check for mxfile/diagram structure
        if '<mxfile' in content:
            root = ET.fromstring(content)
            diagram = root.find('diagram')
            if diagram is not None and diagram.text:
                # Base64 decode
                data = base64.b64decode(diagram.text)
                # Inflate (raw deflate)
                try:
                    data = zlib.decompress(data, -15)
                except:
                    pass # might be just base64
                
                # URL decode might be needed if it's strictly url encoded, 
                # but draw.io desktop usually saves as standard XML or compressed XML.
                from urllib.parse import unquote
                xml_str = unquote(data.decode('utf-8', errors='ignore'))
                return ET.fromstring(xml_str)
            return root
        return ET.fromstring(content)
    except Exception as e:
        return None

def analyze_schematic(file_path):
    if not os.path.exists(file_path):
        return {"exists": False, "error": "File not found"}

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        root = decode_drawio(content)
        if root is None:
            return {"exists": True, "valid_xml": False, "error": "Could not parse XML"}

        # Extract nodes and edges
        nodes = {} # id -> label
        edges = [] # {source, target, color_type}
        
        # Helper to classify color
        def get_color_type(style):
            style = style.lower()
            if 'strokeColor=#ff0000' in style or 'strokecolor=red' in style:
                return 'hot'
            # Some reds are #CC0000 or similar
            if 'strokecolor=#cc0000' in style:
                return 'hot'
            
            if 'strokeColor=#0000ff' in style or 'strokecolor=blue' in style:
                return 'cold'
            if 'strokecolor=#0000cc' in style:
                return 'cold'
            
            return 'unknown'

        for elem in root.iter('mxCell'):
            uid = elem.get('id')
            val = elem.get('value', '')
            style = elem.get('style', '')
            
            # It's an edge
            if elem.get('edge') == '1':
                source = elem.get('source')
                target = elem.get('target')
                if source and target:
                    color = get_color_type(style)
                    edges.append({'source': source, 'target': target, 'type': color})
            
            # It's a vertex (node)
            elif elem.get('vertex') == '1':
                # Filter out generic container/background nodes usually
                # We care about nodes with labels
                clean_label = re.sub(r'<[^>]+>', '', val).strip().lower() # remove html tags
                if clean_label:
                    nodes[uid] = clean_label

        # Logic Analysis
        
        # 1. Identify Fixtures
        fixture_map = {
            'toilet': [],
            'sink': [],
            'shower': [],
            'heater': [],
            'meter': [],
            'main': []
        }
        
        for uid, label in nodes.items():
            for key in fixture_map:
                if key in label:
                    fixture_map[key].append(uid)

        # 2. Check connections for each node
        node_connections = {uid: {'hot': 0, 'cold': 0, 'unknown': 0} for uid in nodes}
        
        for edge in edges:
            s, t = edge['source'], edge['target']
            ctype = edge['type']
            
            if s in node_connections: node_connections[s][ctype] += 1
            if t in node_connections: node_connections[t][ctype] += 1

        # 3. Rule Verification
        violations = []
        
        # Rule: Toilets must not have Hot
        for uid in fixture_map['toilet']:
            if node_connections[uid]['hot'] > 0:
                violations.append(f"Toilet (id {uid}) connected to Hot water")

        # Rule: Sinks should have both (Soft rule, might be missed, but good for scoring)
        sinks_ok = 0
        for uid in fixture_map['sink']:
            if node_connections[uid]['hot'] > 0 and node_connections[uid]['cold'] > 0:
                sinks_ok += 1
        
        return {
            "exists": True,
            "valid_xml": True,
            "node_count": len(nodes),
            "edge_count": len(edges),
            "fixtures_found": {k: len(v) for k, v in fixture_map.items()},
            "color_counts": {
                "hot": len([e for e in edges if e['type'] == 'hot']),
                "cold": len([e for e in edges if e['type'] == 'cold'])
            },
            "violations": violations,
            "sinks_correct": sinks_ok
        }

    except Exception as e:
        return {"exists": True, "valid_xml": False, "error": str(e)}

result = analyze_schematic("/home/ga/Desktop/plumbing_schematic.drawio")
print(json.dumps(result))
PY_EOF

# Check PNG
PNG_EXISTS="false"
if [ -f "$OUTPUT_PNG" ] && [ -s "$OUTPUT_PNG" ]; then
    PNG_EXISTS="true"
fi

# File timestamps check
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_DRAWIO" ]; then
    F_TIME=$(stat -c %Y "$OUTPUT_DRAWIO")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# App running check
APP_RUNNING="false"
if pgrep -f "drawio" > /dev/null; then
    APP_RUNNING="true"
fi

# Combine into final JSON
# We merge the python analysis with the shell file checks
jq -n \
    --slurpfile analysis /tmp/schematic_analysis.json \
    --arg png_exists "$PNG_EXISTS" \
    --arg created_during_task "$FILE_CREATED_DURING_TASK" \
    --arg app_running "$APP_RUNNING" \
    '{
        analysis: $analysis[0],
        png_exists: ($png_exists == "true"),
        file_created_during_task: ($created_during_task == "true"),
        app_running: ($app_running == "true")
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Export complete. Result:"
cat /tmp/task_result.json