#!/usr/bin/env python3
import json
import os
import tempfile
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def decode_drawio_xml(raw_xml):
    """
    Decodes the compressed XML format often used by diagrams.net (mxfile).
    Format: URL-encoded -> Base64 -> Deflate (no header).
    """
    try:
        root = ET.fromstring(raw_xml)
        if root.tag == 'mxfile':
            diagram = root.find('diagram')
            if diagram is not None and diagram.text:
                # Steps to decode:
                # 1. URL unquote
                # 2. Base64 decode
                # 3. Inflate (zlib raw wbits=-15)
                compressed = diagram.text.strip()
                # Draw.io sometimes URL encodes, sometimes not. Try strictly.
                try:
                    decoded_b64 = base64.b64decode(compressed)
                except:
                    # Try unquoting first
                    decoded_b64 = base64.b64decode(urllib.parse.unquote(compressed))
                
                xml_string = zlib.decompress(decoded_b64, -15).decode('utf-8')
                return ET.fromstring(xml_string)
        return root # Return as is if not compressed mxfile
    except Exception as e:
        logger.warning(f"Failed to decode XML: {e}")
        return None

def verify_business_capability_heatmap(traj, env_info, task_info):
    """
    Verifies the Business Capability Map task.
    1. Checks file existence (drawio and pdf).
    2. Parses drawio XML to check:
       - Domain containers existence.
       - Capability shapes existence.
       - Visual Containment (geometry intersection).
       - Color coding accuracy based on Status.
    """
    
    # 1. Setup & Copy Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load Result JSON
    res_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    drawio_file = tempfile.NamedTemporaryFile(delete=False, suffix=".drawio")
    
    try:
        copy_from_env("/tmp/task_result.json", res_file.name)
        with open(res_file.name) as f:
            result_data = json.load(f)
            
        if not result_data.get("drawio_exists"):
            return {"passed": False, "score": 0, "feedback": "No .drawio file found."}
            
        copy_from_env(result_data["drawio_path"], drawio_file.name)
        with open(drawio_file.name, "r") as f:
            raw_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve files: {str(e)}"}
    finally:
        os.unlink(res_file.name)
        # We unlink drawio_file later
        
    # 2. Parse XML
    root = decode_drawio_xml(raw_content)
    os.unlink(drawio_file.name) # clean up
    
    if root is None:
        return {"passed": False, "score": 0, "feedback": "Could not parse diagram XML."}
        
    # 3. Analyze Shapes
    # Flatten all cells
    cells = []
    # Handle both compressed root (mxGraphModel inside root) or uncompressed
    graph_model = root.find(".//mxGraphModel")
    if graph_model is None: 
        graph_model = root # Fallback
        
    for cell in graph_model.findall(".//mxCell"):
        cells.append({
            "id": cell.get("id"),
            "parent": cell.get("parent"),
            "value": cell.get("value", ""),
            "style": cell.get("style", ""),
            "vertex": cell.get("vertex"),
            "geometry": cell.find("mxGeometry")
        })

    # Metadata Requirements
    domains_req = task_info['metadata']['domains']
    caps_req = task_info['metadata']['capabilities']
    colors_req = task_info['metadata']['colors']

    score = 0
    feedback = []

    # Criterion A: PDF Export (10 pts)
    if result_data.get("pdf_exists"):
        score += 10
        feedback.append("PDF export found (+10).")
    else:
        feedback.append("PDF export missing (0).")

    # Helper to find shape by label (case-insensitive substring)
    def find_shape(label, must_be_vertex=True):
        for c in cells:
            if must_be_vertex and c['vertex'] != '1': continue
            if c['value'] and label.lower() in c['value'].lower():
                return c
        return None

    # Criterion B: Domains Exist (20 pts)
    domains_found = 0
    domain_shapes = {}
    for d in domains_req:
        shape = find_shape(d)
        if shape:
            domains_found += 1
            domain_shapes[d] = shape
    
    score += (domains_found / len(domains_req)) * 20
    feedback.append(f"Domains found: {domains_found}/{len(domains_req)} (+{int((domains_found/len(domains_req))*20)}).")

    # Criterion C: Capabilities Exist (20 pts)
    caps_found = 0
    cap_shapes = {}
    for c_name in caps_req:
        shape = find_shape(c_name)
        if shape:
            caps_found += 1
            cap_shapes[c_name] = shape
            
    score += (caps_found / len(caps_req)) * 20
    feedback.append(f"Capabilities found: {caps_found}/{len(caps_req)} (+{int((caps_found/len(caps_req))*20)}).")

    # Criterion D: Nesting/Containment (25 pts)
    # Check if Capability is logically (parent ID) or spatially (geometry) inside Domain
    nesting_score = 0
    
    def get_geo(shape):
        geo = shape['geometry']
        if geo is None: return None
        try:
            return {
                "x": float(geo.get("x", 0)),
                "y": float(geo.get("y", 0)),
                "w": float(geo.get("width", 0)),
                "h": float(geo.get("height", 0))
            }
        except: return None

    for c_name, req in caps_req.items():
        c_shape = cap_shapes.get(c_name)
        d_name = req['domain']
        d_shape = domain_shapes.get(d_name)
        
        if c_shape and d_shape:
            # Check 1: Explicit Parent Link (draw.io groups)
            if c_shape['parent'] == d_shape['id']:
                nesting_score += 1
                continue
                
            # Check 2: Spatial Containment (if no explicit parent)
            c_geo = get_geo(c_shape)
            d_geo = get_geo(d_shape)
            
            if c_geo and d_geo:
                # Basic AABB check
                # Note: Coordinates in draw.io can be relative if grouped. 
                # If explicit parent check failed, likely coordinates are absolute (parent=1)
                if (c_geo['x'] >= d_geo['x'] and 
                    c_geo['y'] >= d_geo['y'] and 
                    (c_geo['x'] + c_geo['w']) <= (d_geo['x'] + d_geo['w']) and 
                    (c_geo['y'] + c_geo['h']) <= (d_geo['y'] + d_geo['h'])):
                    nesting_score += 1
    
    score += (nesting_score / len(caps_req)) * 25
    feedback.append(f"Correct nesting: {nesting_score}/{len(caps_req)} (+{int((nesting_score/len(caps_req))*25)}).")

    # Criterion E: Heatmap Colors (25 pts)
    color_score = 0
    
    for c_name, req in caps_req.items():
        c_shape = cap_shapes.get(c_name)
        if c_shape:
            style = c_shape['style'].lower()
            status = req['status']
            target_colors = colors_req.get(status, [])
            
            # Check if any target color code is in the style string
            # Draw.io styles: "fillColor=#f8cecc;..."
            match = False
            for color in target_colors:
                if f"fillcolor={color}" in style or f"fillcolor=#{color.lstrip('#')}" in style:
                    match = True
                    break
            
            if match:
                color_score += 1
            else:
                # Lenient check: just look for the hex without prefix if rigorous failed
                for color in target_colors:
                    clean_hex = color.lstrip('#')
                    if len(clean_hex) == 6 and clean_hex in style:
                        color_score += 1
                        break

    score += (color_score / len(caps_req)) * 25
    feedback.append(f"Correct colors: {color_score}/{len(caps_req)} (+{int((color_score/len(caps_req))*25)}).")

    # Anti-gaming check: If file wasn't modified after start, zero score
    if not result_data.get("drawio_modified"):
        score = 0
        feedback.append("ANTIGAMING: File not modified after start.")

    return {
        "passed": score >= 70,
        "score": int(score),
        "feedback": " ".join(feedback)
    }