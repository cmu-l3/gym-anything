#!/bin/bash
echo "=== Exporting Game AI Behavior Tree Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIAGRAM_FILE="/home/ga/Diagrams/zombie_behavior_tree.drawio"
EXPORT_FILE="/home/ga/Diagrams/exports/zombie_behavior_tree.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to parse the drawio XML and extract semantic graph data
python3 << 'PYEOF'
import sys
import os
import json
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import re

file_path = "/home/ga/Diagrams/zombie_behavior_tree.drawio"
png_path = "/home/ga/Diagrams/exports/zombie_behavior_tree.png"
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

result = {
    "file_exists": False,
    "file_modified": False,
    "png_exists": False,
    "node_count": 0,
    "selector_count": 0,
    "sequence_count": 0,
    "condition_count": 0,
    "action_count": 0,
    "has_root": False,
    "has_health_check": False,
    "has_combat_branch": False,
    "has_idle_branch": False,
    "styling_score": 0,  # Percentage of correctly colored nodes
    "raw_text": []
}

def decode_drawio(content):
    try:
        # Check if it's plain XML
        if content.strip().startswith("<mxfile"):
            if "<diagram" in content:
                # Extract inner diagram text
                root = ET.fromstring(content)
                diagram = root.find("diagram")
                if diagram is not None and diagram.text:
                    return decode_payload(diagram.text)
                return content # Already uncompressed XML?
        return content
    except Exception as e:
        return ""

def decode_payload(payload):
    try:
        # Draw.io compression: URL decode -> Base64 decode -> Inflate (no header)
        decoded_b64 = base64.b64decode(payload)
        xml_str = zlib.decompress(decoded_b64, -15).decode('utf-8')
        return urllib.parse.unquote(xml_str)
    except Exception:
        return ""

if os.path.exists(file_path):
    result["file_exists"] = True
    mtime = os.path.getmtime(file_path)
    if mtime > task_start:
        result["file_modified"] = True
    
    try:
        with open(file_path, 'r') as f:
            raw_content = f.read()
            
        xml_content = decode_drawio(raw_content)
        # Fallback if decode failed or plain XML
        if not xml_content.strip().startswith("<"):
             # It might be plain XML already if saved uncompressed
             if "<mxGraphModel" in raw_content:
                 xml_content = raw_content
        
        # Parse XML
        # Handle cases where xml_content is the inner <mxGraphModel> or full <mxfile>
        if "<mxfile" in xml_content:
            root = ET.fromstring(xml_content)
            # Find the first diagram/graphmodel
            graph = root.find(".//mxGraphModel")
        elif "<mxGraphModel" in xml_content:
            graph = ET.fromstring(xml_content)
        else:
            graph = None

        if graph is not None:
            nodes = []
            edges = []
            
            # Extract cells
            for cell in graph.findall(".//mxCell"):
                val = cell.get("value", "")
                style = cell.get("style", "")
                is_vertex = cell.get("vertex") == "1"
                is_edge = cell.get("edge") == "1"
                
                if is_vertex:
                    nodes.append({"val": val, "style": style})
                    result["raw_text"].append(val.lower())
                
            result["node_count"] = len(nodes)
            
            # Semantic Analysis
            correct_style_count = 0
            total_style_checks = 0
            
            for node in nodes:
                text = node["val"].lower()
                style = node["style"].lower()
                
                # Check Types
                if "selector" in text:
                    result["selector_count"] += 1
                    total_style_checks += 1
                    if "f5f5f5" in style or "grey" in style or "white" in style: 
                        correct_style_count += 1
                elif "sequence" in text:
                    result["sequence_count"] += 1
                    total_style_checks += 1
                    if "f5f5f5" in style or "grey" in style or "white" in style: 
                        correct_style_count += 1
                elif any(x in text for x in ["health", "visible", "distance", "noise"]):
                    # Likely a condition
                    result["condition_count"] += 1
                    total_style_checks += 1
                    if "fff2cc" in style or "yellow" in style:
                        correct_style_count += 1
                elif any(x in text for x in ["bite", "spit", "move", "wander", "sleep", "cover", "eat"]):
                    # Likely an action
                    result["action_count"] += 1
                    total_style_checks += 1
                    if "dae8fc" in style or "blue" in style:
                        correct_style_count += 1
            
            if total_style_checks > 0:
                result["styling_score"] = (correct_style_count / total_style_checks) * 100
            
            # Text based logic checks (heuristic since graph traversal in simple XML parse is hard)
            txt = " ".join(result["raw_text"])
            
            result["has_root"] = "root" in txt or "behavior tree" in txt
            # Check for Health logic components
            result["has_health_check"] = "health" in txt and ("cover" in txt or "heal" in txt or "brain" in txt)
            # Check for Combat logic components
            result["has_combat_branch"] = "player" in txt and "visible" in txt and "bite" in txt and "spit" in txt
            # Check for Idle logic
            result["has_idle_branch"] = "idle" in txt or ("wander" in txt and "sleep" in txt)

    except Exception as e:
        print(f"Error parsing XML: {e}")

if os.path.exists(png_path):
    result["png_exists"] = True

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json