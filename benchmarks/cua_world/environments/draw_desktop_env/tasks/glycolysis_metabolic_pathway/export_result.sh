#!/bin/bash
# Do NOT use set -e

echo "=== Exporting glycolysis_metabolic_pathway result ==="

# 1. Take final screenshot for VLM verification
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
DRAWIO_FILE="/home/ga/Desktop/glycolysis.drawio"
PNG_FILE="/home/ga/Desktop/glycolysis.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# 3. Analyze Diagram Content using Python
# This script handles both uncompressed XML and compressed (deflate) draw.io files
# It searches for molecules, enzymes, and ATP indicators
python3 << 'PYEOF' > /tmp/glycolysis_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/glycolysis.drawio"
result = {
    "molecules_found": [],
    "enzymes_found": [],
    "atp_found": False,
    "adp_found": False,
    "split_detected": False,
    "num_shapes": 0,
    "num_edges": 0,
    "error": None
}

MOLECULES = [
    "glucose",
    "glucose-6-phosphate", 
    "fructose-6-phosphate", 
    "fructose-1,6-bisphosphate", 
    "dihydroxyacetone phosphate", "dhap",
    "glyceraldehyde-3-phosphate", "g3p"
]

ENZYMES = [
    "hexokinase",
    "phosphoglucose isomerase", "phosphohexose isomerase",
    "phosphofructokinase", "pfk",
    "aldolase",
    "triose phosphate isomerase", "tpi"
]

def decompress_diagram(content):
    if not content or not content.strip(): return None
    try:
        # Try base64 -> inflate
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except:
        pass
    try:
        # Try URL decode
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except:
        pass
    return None

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        all_cells = []
        
        # Extract cells from all pages (compressed or inline)
        for diagram in root.findall('diagram'):
            # Check for compressed content
            if diagram.text and diagram.text.strip():
                decompressed_root = decompress_diagram(diagram.text)
                if decompressed_root:
                    all_cells.extend(list(decompressed_root.iter('mxCell')))
            
            # Check for inline content (fallback/mixed)
            inline_root = diagram.find('mxGraphModel')
            if inline_root:
                all_cells.extend(list(inline_root.iter('mxCell')))
        
        # Flatten and extract text
        text_content = []
        
        # Also map IDs to verify split topology
        # id -> {target: [], source: [], value: ""}
        graph_map = {} 
        
        for cell in all_cells:
            cid = cell.get('id')
            val = (cell.get('value') or "").lower()
            style = (cell.get('style') or "").lower()
            
            # Clean HTML from value
            clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
            if clean_val:
                text_content.append(clean_val)
                
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                graph_map[cid] = {"type": "vertex", "val": clean_val, "out": []}
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                source = cell.get('source')
                target = cell.get('target')
                if source:
                    # Record connection for topology check
                    if source not in graph_map: graph_map[source] = {"type": "vertex", "val": "unknown", "out": []}
                    graph_map[source]["out"].append(target)

        combined_text = " ".join(text_content)
        
        # Check Molecules
        for mol in MOLECULES:
            # Simple substring match in full text dump
            if mol in combined_text:
                # Normalize names for reporting
                norm_name = mol
                if mol in ["dhap", "dihydroxyacetone phosphate"]: norm_name = "DHAP"
                elif mol in ["g3p", "glyceraldehyde-3-phosphate"]: norm_name = "G3P"
                
                if norm_name not in result["molecules_found"]:
                    result["molecules_found"].append(norm_name)
                    
        # Check Enzymes
        for enz in ENZYMES:
            if enz in combined_text:
                result["enzymes_found"].append(enz)
                
        # Check ATP/ADP
        if "atp" in combined_text: result["atp_found"] = True
        if "adp" in combined_text: result["adp_found"] = True
        
        # Check Split Topology (Bonus/Robustness)
        # Look for a node containing "bisphosphate" that has >= 2 outgoing edges OR 
        # is connected to two distinct nodes containing "phosphate"
        # Since graph mapping is hard with loose parsing, we'll rely on text "split" or visual layout count.
        # But we can try a heuristic: Does Fructose-1,6-BP exist and is the word "Aldolase" near it?
        # A simpler check: Do we have enough edges? 5 steps = min 5 edges.
        
        # Heuristic for split: Aldolase is the splitting enzyme.
        if "aldolase" in combined_text and "dihydroxyacetone" in combined_text and "glyceraldehyde" in combined_text:
            result["split_detected"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Compile Final JSON Result
# Merge bash checks with python analysis
python3 << 'JSONEOF' > /tmp/task_result.json
import json

# Load python analysis
try:
    with open('/tmp/glycolysis_analysis.json') as f:
        analysis = json.load(f)
except:
    analysis = {}

output = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_modified": "$FILE_MODIFIED" == "true",
    "png_exists": "$PNG_EXISTS" == "true",
    "png_size": int("$PNG_SIZE"),
    "molecules_found": analysis.get("molecules_found", []),
    "enzymes_found": analysis.get("enzymes_found", []),
    "atp_found": analysis.get("atp_found", False),
    "adp_found": analysis.get("adp_found", False),
    "split_detected": analysis.get("split_detected", False),
    "num_shapes": analysis.get("num_shapes", 0),
    "timestamp": "$TASK_START"
}

print(json.dumps(output))
JSONEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json