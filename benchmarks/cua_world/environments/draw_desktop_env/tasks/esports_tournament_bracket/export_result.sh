#!/bin/bash
# Export script for esports_tournament_bracket

echo "=== Exporting Task Results ==="

# 1. Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze the diagram XML
# This does the heavy lifting: parsing the .drawio file (XML), extracting text/positions/colors,
# and comparing against the ground truth JSON.
python3 << 'PYEOF' > /tmp/task_result.json
import json
import os
import sys
import base64
import zlib
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

# Paths
DRAWIO_PATH = "/home/ga/Desktop/winter_major_bracket.drawio"
PNG_PATH = "/home/ga/Desktop/winter_major_bracket.png"
GROUND_TRUTH_PATH = "/tmp/bracket_ground_truth.json"
START_TIME_PATH = "/tmp/task_start_time.txt"

result = {
    "files_exist": False,
    "png_exists": False,
    "file_modified_correctly": False,
    "structure_score": 0,
    "logic_score": 0,
    "style_score": 0,
    "error": None,
    "details": {}
}

def decompress_diagram(content):
    """Decompress draw.io XML content."""
    if not content: return None
    # Method 1: URL encoded
    try:
        if content.strip().startswith('%3C'):
            return ET.fromstring(unquote(content))
    except: pass
    
    # Method 2: Base64 + Deflate
    try:
        decoded = base64.b64decode(content)
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except: pass
    
    # Method 3: Raw XML
    try:
        if content.strip().startswith('<'):
            return ET.fromstring(content)
    except: pass
    
    return None

try:
    # 1. File Checks
    if os.path.exists(DRAWIO_PATH):
        result["files_exist"] = True
        
        # Timestamp check
        if os.path.exists(START_TIME_PATH):
            with open(START_TIME_PATH, 'r') as f:
                start_time = int(f.read().strip())
            mtime = int(os.path.getmtime(DRAWIO_PATH))
            if mtime > start_time:
                result["file_modified_correctly"] = True
    
    if os.path.exists(PNG_PATH):
        result["png_exists"] = True

    # 2. Parse Logic
    if result["files_exist"]:
        # Load Ground Truth
        with open(GROUND_TRUTH_PATH, 'r') as f:
            gt = json.load(f)
            
        # Parse Drawio
        tree = ET.parse(DRAWIO_PATH)
        root = tree.getroot()
        
        # Handle compressed diagram data
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            graph_root = decompress_diagram(diagram_node.text)
            if graph_root is None:
                # If decompression fails, maybe it's just raw inside mxGraphModel
                mx_graph = root.find('.//mxGraphModel')
                if mx_graph:
                    graph_root = mx_graph
                else:
                    raise Exception("Could not decompress diagram data")
        else:
             graph_root = root.find('.//mxGraphModel')
             if not graph_root:
                 graph_root = root # Fallback
        
        # Extract Shapes (Vertices)
        # We need: Text (value), X-coord, FillColor
        shapes = []
        root_cells = graph_root.findall(".//mxCell[@vertex='1']")
        
        for cell in root_cells:
            style = cell.get('style', '')
            geom = cell.find('mxGeometry')
            val = cell.get('value', '')
            
            if geom is not None:
                x = float(geom.get('x', 0))
                y = float(geom.get('y', 0))
                
                # Check for gold/yellow fill
                # Hex codes for gold/yellow or keywords
                is_gold = False
                style_lower = style.lower()
                if 'fillcolor=#ffd700' in style_lower or \
                   'fillcolor=#ffff00' in style_lower or \
                   'fillcolor=#ffcc00' in style_lower or \
                   'fillcolor=yellow' in style_lower or \
                   'fillcolor=gold' in style_lower:
                    is_gold = True
                
                # Clean text (remove HTML tags)
                text = re.sub('<[^<]+?>', '', val).strip()
                
                if text: # Ignore empty shapes
                    shapes.append({
                        "text": text,
                        "x": x,
                        "y": y,
                        "is_gold": is_gold
                    })

        # 3. Analyze Structure (Clustering by X-coordinate)
        if shapes:
            # Sort by X
            shapes.sort(key=lambda k: k['x'])
            
            # Simple clustering: if x diff > 50px, new column
            columns = []
            if len(shapes) > 0:
                current_col = [shapes[0]]
                for i in range(1, len(shapes)):
                    if shapes[i]['x'] - shapes[i-1]['x'] > 50:
                        columns.append(current_col)
                        current_col = []
                    current_col.append(shapes[i])
                columns.append(current_col)
            
            result["details"]["columns_found"] = len(columns)
            
            # Check Column Counts (Ideal: 8 -> 4 -> 2 -> 1)
            # We allow some flexibility (e.g., maybe title shapes are present)
            # We look for columns that contain the ground truth team names
            
            col_matches = {
                "qf": 0,
                "sf": 0,
                "final": 0,
                "champ": 0
            }
            
            # Flatten text for searching
            all_text_lower = [s['text'].lower() for s in shapes]
            
            # Logic Check: Quarters
            # Ground truth QF winners (4 teams)
            gt_sf_teams = set(t.lower() for t in gt["semifinals"])
            gt_final_teams = set(t.lower() for t in gt["finals"]) # 2 teams (champ + runner up from SF)
            gt_champ = gt["champion"].lower()
            
            # We expect the QF winners to appear in the 2nd column (or later)
            # We expect the Final winners to appear in the 3rd column
            # We expect the Champ to appear in the 4th column
            
            if len(columns) >= 3:
                result["structure_score"] = 100 # Found at least 3 layers of depth
                
                # Check if Champ is in the right-most column
                last_col = columns[-1]
                champ_found = False
                gold_found = False
                
                for s in last_col:
                    if gt_champ in s['text'].lower():
                        champ_found = True
                        if s['is_gold']:
                            gold_found = True
                
                if champ_found:
                    result["logic_score"] += 40
                if gold_found:
                    result["style_score"] = 100
                    
                # Check Semifinalists (should exist in the diagram)
                sf_count = 0
                for team in gt_sf_teams:
                    # Look for this team appearing TWICE or more in the diagram?
                    # Actually, usually in a bracket:
                    # QF Round: Team Name (Start) -> SF Round: Team Name (Winner)
                    # So winners appear multiple times as they advance.
                    # Or valid if they appear in the later columns.
                    
                    # Let's just check if the text exists in the diagram generally, 
                    # and specifically if the Champion exists
                    if any(team in txt for txt in all_text_lower):
                        sf_count += 1
                
                if sf_count >= 4:
                    result["logic_score"] += 30
                    
                # Check if correct Champ is gold (already checked above in last col)
                # Backup check: Is there ANY gold shape with the champ name?
                if result["style_score"] == 0:
                    for s in shapes:
                        if s['is_gold'] and gt_champ in s['text'].lower():
                            result["style_score"] = 100
                            break

                # Connectivity check (basic edge count)
                edges = graph_root.findall(".//mxCell[@edge='1']")
                result["details"]["edge_count"] = len(edges)
                if len(edges) >= 7: # 8->4 (4 edges), 4->2 (2 edges), 2->1 (1 edge) = 7 minimum
                    result["logic_score"] += 30

            else:
                # Fallback if columns not clearly detected, just check text existence
                result["structure_score"] = 0
                if gt_champ in ' '.join(all_text_lower):
                     result["logic_score"] += 20
        
        result["details"]["shape_count"] = len(shapes)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/task_result.json
echo "Analysis complete. JSON saved."
cat /tmp/task_result.json