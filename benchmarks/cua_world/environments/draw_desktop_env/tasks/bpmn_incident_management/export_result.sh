#!/bin/bash
# Export script for BPMN Incident Management task

echo "=== Exporting Task Results ==="

# Paths
DRAWIO_FILE="/home/ga/Desktop/incident_management.drawio"
PNG_FILE="/home/ga/Desktop/incident_management.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze the .drawio file (XML parsing + decompression)
python3 << 'PYEOF' > /tmp/bpmn_analysis.json 2>/dev/null || true
import json
import os
import base64
import zlib
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Desktop/incident_management.drawio"
task_start = int(os.environ.get("TASK_START", 0))

result = {
    "file_exists": False,
    "file_modified_during_task": False,
    "png_exists": False,
    "png_size": 0,
    "pool_count": 0,
    "lane_count": 0,
    "task_count": 0,
    "gateway_count": 0,
    "event_count": 0,
    "edge_count": 0,
    "message_flow_count": 0,
    "keywords_found": [],
    "page_count": 0,
    "has_bpmn_shapes": False
}

# Check PNG
if os.path.exists("/home/ga/Desktop/incident_management.png"):
    result["png_exists"] = True
    result["png_size"] = os.path.getsize("/home/ga/Desktop/incident_management.png")

if os.path.exists(file_path):
    result["file_exists"] = True
    mtime = int(os.path.getmtime(file_path))
    if mtime > task_start:
        result["file_modified_during_task"] = True
    
    try:
        # Load and parse XML
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result["page_count"] = len(diagrams)
        
        all_text = ""
        
        # Helper to extract cells from compressed or raw diagram nodes
        def get_cells(diagram_node):
            if diagram_node.find('mxGraphModel') is not None:
                return diagram_node.find('mxGraphModel').find('root').findall('mxCell')
            
            # Try compressed
            if diagram_node.text:
                try:
                    data = base64.b64decode(diagram_node.text)
                    xml_str = zlib.decompress(data, -15).decode('utf-8')
                    # sometimes it's URL encoded inside
                    xml_str = unquote(xml_str)
                    return ET.fromstring(xml_str).find('root').findall('mxCell')
                except Exception as e:
                    pass
            return []

        for diagram in diagrams:
            cells = get_cells(diagram)
            for cell in cells:
                style = cell.get('style', '').lower()
                value = (cell.get('value', '') or '').lower()
                vertex = cell.get('vertex') == '1'
                edge = cell.get('edge') == '1'
                
                # Collect text for keyword search
                all_text += " " + value
                
                if vertex:
                    # Detect Pools/Lanes
                    if 'swimlane' in style or 'pool' in style:
                        # Pools usually have no parent or layer parent, Lanes have pool parent
                        # Heuristic: verify text content for "Service Desk", "L1", etc.
                        if 'childlayout' not in style: # rough filter
                            if 'lane' in style or 'swimlane' in style: 
                                result["lane_count"] += 1
                            else:
                                result["pool_count"] += 1
                                
                    # Detect BPMN specific shapes
                    if 'bpmn' in style:
                        result["has_bpmn_shapes"] = True
                        if 'task' in style:
                            result["task_count"] += 1
                        elif 'gateway' in style or 'rhombus' in style: # standard diamond shape often used
                            result["gateway_count"] += 1
                        elif 'event' in style or 'ellipse' in style: # standard circle
                            result["event_count"] += 1
                    else:
                        # Fallback for standard shapes used as BPMN
                        if 'process' in style or 'rectangle' in style or 'rounded=1' in style:
                            # Only count if it has text, likely a task
                            if len(value) > 3:
                                result["task_count"] += 1
                        elif 'rhombus' in style:
                            result["gateway_count"] += 1
                        elif 'ellipse' in style:
                            result["event_count"] += 1
                            
                if edge:
                    result["edge_count"] += 1
                    # Message flow is usually dashed
                    if 'dashed=1' in style or 'message' in style:
                        result["message_flow_count"] += 1

        # Check keywords
        keywords = ["incident", "l1", "l2", "manager", "resolve", "diagnose", "sla", "close", "service desk"]
        for kw in keywords:
            if kw in all_text:
                result["keywords_found"].append(kw)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Move result to final location with permissions
mv /tmp/bpmn_analysis.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"