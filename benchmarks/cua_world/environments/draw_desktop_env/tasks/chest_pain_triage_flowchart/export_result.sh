#!/bin/bash
# export_result.sh for chest_pain_triage_flowchart
# This script analyzes the draw.io file and exports metrics to JSON.

echo "=== Exporting Task Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
DRAWIO_FILE="/home/ga/Desktop/chest_pain_triage.drawio"
PNG_FILE="/home/ga/Desktop/chest_pain_triage.png"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze output using embedded Python script
# We need Python to handle draw.io's XML structure which can be compressed.
python3 << 'EOF' > /tmp/task_result.json
import json
import os
import sys
import zlib
import base64
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

drawio_path = "/home/ga/Desktop/chest_pain_triage.drawio"
png_path = "/home/ga/Desktop/chest_pain_triage.png"
start_time = int(os.environ.get('START_TIME', 0))

result = {
    "file_exists": False,
    "file_modified_correctly": False,
    "png_exists": False,
    "png_size": 0,
    "shape_count": 0,
    "diamond_count": 0,
    "edge_count": 0,
    "page_count": 0,
    "distinct_colors": 0,
    "keywords_found": [],
    "terminal_nodes": 0
}

def decode_diagram_data(data):
    """Decode draw.io diagram data (Deflate+Base64 or URL encoded)."""
    if not data: return None
    try:
        # Try Base64 + Inflate
        decoded = base64.b64decode(data)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except:
        try:
            # Try URL decode
            return unquote(data)
        except:
            return None

if os.path.exists(drawio_path):
    result["file_exists"] = True
    stat = os.stat(drawio_path)
    if stat.st_mtime > start_time:
        result["file_modified_correctly"] = True

    try:
        tree = ET.parse(drawio_path)
        root = tree.getroot()
        
        # Count Pages
        diagrams = root.findall('diagram')
        result["page_count"] = len(diagrams)
        
        all_xml_content = []
        
        # Extract content from all pages
        for diagram in diagrams:
            raw_text = diagram.text
            if raw_text:
                decoded = decode_diagram_data(raw_text)
                if decoded:
                    all_xml_content.append(decoded)
                else:
                    # Might be uncompressed
                    all_xml_content.append(raw_text)
        
        # If no diagram tags, check if root is mxGraphModel (uncompressed file)
        if not diagrams and root.tag == 'mxGraphModel':
             all_xml_content.append(ET.tostring(root, encoding='unicode'))

        # Analyze Content
        full_text_corpus = ""
        colors_seen = set()
        
        for xml_str in all_xml_content:
            try:
                # Wrap fragment in root if needed
                if not xml_str.strip().startswith('<'): continue
                
                # Simple string analysis for counting styles to avoid complex XML namespace parsing
                # Count shapes (vertices)
                result["shape_count"] += xml_str.count('vertex="1"')
                
                # Count edges
                result["edge_count"] += xml_str.count('edge="1"')
                
                # Find Rhombus/Diamond shapes (decisions)
                # Styles often contain 'rhombus', 'diamond', or 'decision'
                result["diamond_count"] += len(re.findall(r'style="[^"]*(?:rhombus|diamond|decision)[^"]*"', xml_str, re.IGNORECASE))
                
                # Find Colors (fillColor)
                fills = re.findall(r'fillColor=([^;"]+)', xml_str)
                for f in fills:
                    if f.lower() not in ['none', '#ffffff', 'default', 'white']:
                        colors_seen.add(f.lower())

                # Extract Text labels (value attribute)
                # Parse XML properly for values to handle HTML entities
                try:
                    # Remove garbage characters that might break parser
                    clean_xml = re.sub(r'&#\d+;', '', xml_str) 
                    # If it's just the inner part, wrap it
                    if '<mxGraphModel>' not in clean_xml:
                        clean_xml = f"<root>{clean_xml}</root>"
                    
                    page_root = ET.fromstring(clean_xml)
                    for cell in page_root.iter('mxCell'):
                        val = cell.get('value', '')
                        if val:
                            full_text_corpus += " " + val
                except:
                    # Fallback regex extraction for text
                    vals = re.findall(r'value="([^"]*)"', xml_str)
                    full_text_corpus += " " + " ".join(vals)
                    
            except Exception as e:
                pass # Skip malformed page
        
        result["distinct_colors"] = len(colors_seen)
        
        # Keyword Search (Case Insensitive)
        full_text_lower = full_text_corpus.lower()
        targets = ["stemi", "nstemi", "troponin", "heart", "ecg", "acs"]
        for t in targets:
            if t in full_text_lower:
                result["keywords_found"].append(t)
                
        # Count Terminal Nodes (End points often labeled Admit, Discharge, etc)
        terminals = ["discharge", "admit", "observation", "cath lab", "home", "unit"]
        for t in terminals:
            result["terminal_nodes"] += full_text_lower.count(t)

    except Exception as e:
        result["error"] = str(e)

# Check PNG
if os.path.exists(png_path):
    result["png_exists"] = True
    result["png_size"] = os.path.getsize(png_path)

print(json.dumps(result))
EOF

echo "Result JSON generated at /tmp/task_result.json"