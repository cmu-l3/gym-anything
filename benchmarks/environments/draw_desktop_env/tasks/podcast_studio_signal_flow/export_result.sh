#!/bin/bash
echo "=== Exporting Podcast Studio Task Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DRAWIO_FILE="/home/ga/Desktop/studio_signal_flow.drawio"
PNG_FILE="/home/ga/Desktop/studio_signal_flow.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Run Python script to parse the draw.io XML structure
# This extracts the graph topology to verify correct wiring
python3 << 'PYEOF' > /tmp/topology_analysis.json 2>/dev/null || true
import sys
import json
import base64
import zlib
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/studio_signal_flow.drawio"
result = {
    "node_counts": {
        "mic": 0, "cloudlifter": 0, "mixer": 0, "pc": 0, 
        "amp": 0, "headphone": 0, "monitor": 0
    },
    "edges": [],
    "cable_labels": [],
    "mic_chains_correct": 0,
    "output_chains_correct": 0,
    "error": None
}

def decode_drawio(content):
    """Decompress draw.io XML content"""
    try:
        # Check if it's plain XML
        if content.strip().startswith('<mxGraphModel'):
            return ET.fromstring(content)
        
        # Try unpacking compressed content
        tree = ET.fromstring(content)
        diagram = tree.find('diagram')
        if diagram is not None and diagram.text:
            b64 = diagram.text
            try:
                # Standard base64 -> inflate
                decoded = base64.b64decode(b64)
                xml_str = zlib.decompress(decoded, -15).decode('utf-8')
                return ET.fromstring(unquote(xml_str))
            except:
                # Fallback for plain text
                return None
    except Exception as e:
        return None
    return None

try:
    with open(filepath, 'r') as f:
        content = f.read()
    
    root = decode_drawio(content)
    if root is None:
        result["error"] = "Could not parse/decompress file"
    else:
        # 1. Parse Nodes
        # Map ID -> {type, label}
        nodes = {}
        
        # Define keywords for classification
        keywords = {
            "mic": ["sm7b", "mic", "shure"],
            "cloudlifter": ["cloudlifter", "cl-1", "activator", "preamp"],
            "mixer": ["rodecaster", "mixer", "console", "pro ii"],
            "pc": ["pc", "computer", "daw", "reaper", "windows"],
            "amp": ["ha8000", "amp", "distribution"],
            "headphone": ["headphone", "sony", "mdr"],
            "monitor": ["monitor", "yamaha", "hs8", "speaker"]
        }

        for cell in root.iter('mxCell'):
            c_id = cell.get('id')
            val = (cell.get('value') or "").lower()
            style = (cell.get('style') or "").lower()
            
            # Identify nodes (vertices)
            if cell.get('vertex') == '1':
                node_type = "unknown"
                for k, words in keywords.items():
                    if any(w in val for w in words):
                        node_type = k
                        break
                
                if node_type != "unknown":
                    nodes[c_id] = {"type": node_type, "label": val}
                    result["node_counts"][node_type] += 1
                elif val:
                    # Capture unclassified nodes just in case
                    nodes[c_id] = {"type": "other", "label": val}

        # 2. Parse Edges
        edges = []
        for cell in root.iter('mxCell'):
            if cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                label = (cell.get('value') or "").strip()
                
                if source in nodes and target in nodes:
                    edge_info = {
                        "source": nodes[source]["type"],
                        "target": nodes[target]["type"],
                        "label": label
                    }
                    edges.append(edge_info)
                    if label:
                        result["cable_labels"].append(label)

        result["edges"] = edges

        # 3. Analyze Topology
        # Check Mic -> Cloudlifter -> Mixer chains
        # We look for path: mic -> cloudlifter and cloudlifter -> mixer
        mic_links = [e for e in edges if e["source"] == "mic" and e["target"] == "cloudlifter"]
        lift_links = [e for e in edges if e["source"] == "cloudlifter" and e["target"] == "mixer"]
        
        # A valid chain needs a cloudlifter that is both a target of a mic and source to a mixer
        # Simplified counting: min(mic->lift, lift->mixer)
        result["mic_chains_correct"] = min(len(mic_links), len(lift_links))

        # Check Output Chains
        # Mixer -> PC
        mixer_pc = any(e for e in edges if e["source"] == "mixer" and e["target"] == "pc")
        
        # Mixer -> Amp -> Headphone
        mixer_amp = any(e for e in edges if e["source"] == "mixer" and e["target"] == "amp")
        amp_phones = len([e for e in edges if e["source"] == "amp" and e["target"] == "headphone"])
        
        # Mixer -> Monitors
        mixer_monitors = any(e for e in edges if e["source"] == "mixer" and e["target"] == "monitor")
        
        if mixer_pc: result["output_chains_correct"] += 1
        if mixer_monitors: result["output_chains_correct"] += 1
        if mixer_amp and amp_phones >= 1: result["output_chains_correct"] += 1

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Prepare final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "analysis_path": "/tmp/topology_analysis.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/topology_analysis.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"