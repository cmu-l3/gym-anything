#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import math

def decode_drawio_xml(xml_content):
    """
    Decodes a draw.io file. 
    It can be:
    1. Plain XML (uncompressed)
    2. MXFILE with compressed diagram text
    """
    try:
        tree = ET.ElementTree(ET.fromstring(xml_content))
        root = tree.getroot()
        
        # If it's an mxfile, it might contain compressed diagrams
        if root.tag == 'mxfile':
            diagrams = []
            for diagram in root.findall('diagram'):
                if diagram.text:
                    try:
                        # Decode Base64
                        data = base64.b64decode(diagram.text)
                        # Decompress (raw deflate)
                        # We use -15 for raw deflate (no header)
                        xml_str = zlib.decompress(data, -15).decode('utf-8')
                        # URL decode just in case (draw.io sometimes does both)
                        xml_str = urllib.parse.unquote(xml_str)
                        diagrams.append(xml_str)
                    except Exception as e:
                        # Fallback: maybe it wasn't compressed or failed
                        diagrams.append(diagram.text)
            
            # Combine all diagrams or take the first one
            if diagrams:
                return diagrams[0] # Analyze the first page
        
        # If not mxfile or plain xml
        return xml_content
    except Exception as e:
        print(f"Error decoding XML: {e}")
        return xml_content

def parse_geometry(xml_string):
    """
    Parses the XML content to find shapes and their coordinates.
    Returns a list of dicts: {'label': str, 'x': float, 'y': float, 'w': float, 'h': float}
    """
    shapes = []
    try:
        # Wrap in a root if needed, or just parse
        # If the decoded string is a fragment (mxGraphModel), we might need to be careful
        if not xml_string.strip().startswith('<'):
            # If it failed to decode properly, return empty
            return []
            
        # If it starts with <mxGraphModel>, it's good
        # If it starts with <root>, good.
        
        # Helper to parse XML regardless of root
        try:
            root = ET.fromstring(xml_string)
        except ET.ParseError:
            # Try wrapping
            root = ET.fromstring(f"<root>{xml_string}</root>")

        # Iterate all cells
        for cell in root.iter('mxCell'):
            style = cell.get('style', '')
            value = cell.get('value', '')
            geometry = cell.find('mxGeometry')
            
            if geometry is not None:
                x = float(geometry.get('x', 0))
                y = float(geometry.get('y', 0))
                w = float(geometry.get('width', 0))
                h = float(geometry.get('height', 0))
                
                # Filter out pure edges usually (unless they have relevant labels)
                is_edge = cell.get('edge') == '1'
                
                shapes.append({
                    'id': cell.get('id'),
                    'value': value,
                    'style': style,
                    'x': x,
                    'y': y,
                    'w': w,
                    'h': h,
                    'is_edge': is_edge
                })
    except Exception as e:
        print(f"Error parsing geometry: {e}")
        
    return shapes

def verify_forensic_crime_scene_sketch(traj, env_info, task_info):
    """
    Verifies the geometry of the crime scene sketch.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Env interface error"}

    # 1. Load basic result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Could not retrieve task result JSON."}

    # 2. Score existence (20 pts)
    score = 0
    feedback = []
    
    if not task_result.get('drawio_exists'):
        return {"passed": False, "score": 0, "feedback": "No .drawio file found."}
    
    if task_result.get('drawio_modified'):
        score += 10
        feedback.append("File created/modified.")
    
    if task_result.get('pdf_exists'):
        score += 10
        feedback.append("PDF export found.")

    # 3. Retrieve and Parse Diagram File
    drawio_path = task_result.get('drawio_path')
    raw_xml = ""
    with tempfile.NamedTemporaryFile(suffix=".drawio") as f:
        try:
            copy_from_env(drawio_path, f.name)
            f.seek(0)
            raw_xml = f.read().decode('utf-8')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Could not read .drawio file content: {e}"}

    decoded_xml = decode_drawio_xml(raw_xml)
    shapes = parse_geometry(decoded_xml)
    
    if not shapes:
        return {"passed": False, "score": score, "feedback": "Could not parse shapes from diagram file. It might be empty or corrupted."}

    # 4. Analyze Geometry
    # Constants from Task
    SCALE = 50 # px per meter
    ROOM_W_M = 6.0
    ROOM_H_M = 4.5
    ROOM_W_PX = ROOM_W_M * SCALE # 300
    ROOM_H_PX = ROOM_H_M * SCALE # 225
    TOLERANCE_PX = 30 # relaxed slightly
    
    # A. Find the Room (Largest Rectangle approx 300x225)
    room_shape = None
    best_room_diff = float('inf')
    
    for s in shapes:
        if s['is_edge']: continue
        # Check dimensions
        w_diff = abs(s['w'] - ROOM_W_PX)
        h_diff = abs(s['h'] - ROOM_H_PX)
        total_diff = w_diff + h_diff
        
        # Also allow rotated room? Assume axis aligned for now
        if total_diff < best_room_diff and total_diff < 100: # Broad initial filter
            best_room_diff = total_diff
            room_shape = s
            
    if room_shape:
        score += 20
        feedback.append(f"Room boundaries found (dim: {room_shape['w']}x{room_shape['h']} px).")
        origin_x = room_shape['x']
        origin_y = room_shape['y']
    else:
        feedback.append(f"Could not locate the main room rectangle (Expected ~{ROOM_W_PX}x{ROOM_H_PX} px). Geometry checks failed.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # B. Verify Objects relative to Room Origin
    expected_objects = task_info.get('metadata', {}).get('expected_objects', {})
    
    # Helper to find shape by label
    def find_shape_by_label(target_label):
        for s in shapes:
            if not s['value']: continue
            # Check if label is in value (ignoring HTML tags roughly)
            clean_val = s['value'].lower().replace('<br>', ' ').replace('<div>', '').replace('</div>', '')
            if target_label.lower() in clean_val:
                return s
        return None

    objects_found = 0
    
    for name, data in expected_objects.items():
        label = data['label']
        exp_x_m = data['x_m']
        exp_y_m = data['y_m']
        
        exp_x_px = exp_x_m * SCALE
        exp_y_px = exp_y_m * SCALE
        
        found_shape = find_shape_by_label(label)
        
        if found_shape:
            # Calculate relative position
            # Coordinates of shape are typically its top-left or center depending on style
            # Standard rectangles/ellipses: x,y is top-left.
            # Evidence markers are points. Let's assume user placed center or top-left close.
            # We'll check center of shape against expected point.
            
            center_x = found_shape['x'] + (found_shape['w'] / 2)
            center_y = found_shape['y'] + (found_shape['h'] / 2)
            
            rel_x = center_x - origin_x
            rel_y = center_y - origin_y
            
            dist = math.sqrt((rel_x - exp_x_px)**2 + (rel_y - exp_y_px)**2)
            
            if dist <= TOLERANCE_PX:
                score += 15
                objects_found += 1
                feedback.append(f"Correct placement: {name}.")
            else:
                # Fallback: Maybe they placed Top-Left at coordinates?
                tl_rel_x = found_shape['x'] - origin_x
                tl_rel_y = found_shape['y'] - origin_y
                dist_tl = math.sqrt((tl_rel_x - exp_x_px)**2 + (tl_rel_y - exp_y_px)**2)
                
                if dist_tl <= TOLERANCE_PX:
                    score += 15
                    objects_found += 1
                    feedback.append(f"Correct placement: {name} (Top-Left aligned).")
                else:
                    feedback.append(f"Wrong pos for {name}: Off by {int(dist)}px.")
        else:
            feedback.append(f"Missing object: {name}.")

    # 4. Final Threshold Check
    # Total possible: 20 (files) + 20 (room) + 15*4 (objects) = 100
    if score >= 70:
        passed = True
    else:
        passed = False
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }