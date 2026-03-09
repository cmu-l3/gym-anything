#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import base64
import zlib
import urllib.parse
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_content(encoded_text):
    """
    Decodes the compressed content found in .drawio files.
    Format is usually: URL encoded -> Base64 encoded -> Deflate compressed (no header).
    """
    try:
        # 1. URL Decode
        url_decoded = urllib.parse.unquote(encoded_text)
        # 2. Base64 Decode
        compressed_data = base64.b64decode(url_decoded)
        # 3. Inflate (raw deflate, so negative window bits)
        xml_str = zlib.decompress(compressed_data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        logger.error(f"Error decoding drawio content: {e}")
        return None

def parse_drawio_xml(file_path):
    """
    Parses a .drawio file and returns a list of cells (shapes and edges).
    Handles both compressed and uncompressed formats.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Check if compressed
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            # Compressed format
            xml_content = decode_drawio_content(diagram_node.text)
            if xml_content:
                root = ET.fromstring(xml_content)
            else:
                return []
        
        # Now we should have the graph model
        cells = []
        for cell in root.findall(".//mxCell"):
            cells.append(cell)
        return cells
    except Exception as e:
        logger.error(f"Failed to parse XML: {e}")
        return []

def get_geometry(cell):
    """Extracts geometry (x, y, width, height) from a cell."""
    geo = cell.find("mxGeometry")
    if geo is not None:
        try:
            x = float(geo.get("x", 0))
            y = float(geo.get("y", 0))
            w = float(geo.get("width", 0))
            h = float(geo.get("height", 0))
            return {"x": x, "y": y, "w": w, "h": h, "cx": x + w/2, "cy": y + h/2}
        except ValueError:
            pass
    return None

def normalize_text(text):
    """Normalize text for comparison (lowercase, strip)."""
    if not text:
        return ""
    return text.lower().strip()

def verify_rpg_dungeon_level_design(traj, env_info, task_info):
    """
    Verifies the RPG Dungeon Level Design task.
    Checks for file existence, room presence, topology, spatial layout, and item containment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing."}

    # 1. Load Metadata
    metadata = task_info.get('metadata', {})
    required_rooms = metadata.get('required_rooms', [])
    spatial_rules = metadata.get('spatial_rules', []) # List of {source, target, relation}
    containment_rules = metadata.get('containment_rules', []) # List of {room, item_type}

    # 2. Get JSON Result
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        temp_json_path = f.name
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json_path): os.unlink(temp_json_path)

    # 3. Get Drawio File
    drawio_path = "/home/ga/Diagrams/dungeon_map.drawio"
    local_drawio_path = tempfile.mktemp(suffix=".drawio")
    try:
        copy_from_env(drawio_path, local_drawio_path)
        cells = parse_drawio_xml(local_drawio_path)
    except Exception:
        cells = []
    finally:
        if os.path.exists(local_drawio_path): os.unlink(local_drawio_path)

    # --- Scoring Logic ---
    score = 0
    feedback = []

    # Criterion 1: Files Exist (10 pts)
    if result_data.get("drawio_exists") and result_data.get("drawio_created_during_task"):
        score += 5
        feedback.append("Drawio file created.")
    else:
        feedback.append("Drawio file missing or not fresh.")
    
    if result_data.get("png_exists") and result_data.get("png_size", 0) > 0:
        score += 5
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    if not cells:
        return {"passed": False, "score": score, "feedback": " ".join(feedback) + " (Empty or invalid file)"}

    # Analyze Cells
    rooms_found = {} # label -> geometry
    items_found = [] # list of {type_hint, geometry}
    edges_found = [] # list of {source_id, target_id} (if drawio connects them)

    # Simple text heuristics for identifying rooms vs items
    # Rooms usually are named explicitly. Items are shapes (Circle, etc) or labeled "Key", "Fountain".
    
    for cell in cells:
        val = normalize_text(cell.get("value", ""))
        style = normalize_text(cell.get("style", ""))
        geo = get_geometry(cell)
        
        # Skip empty geometry
        if not geo: 
            continue

        # Identify Rooms
        matched_room = None
        for r in required_rooms:
            if normalize_text(r) in val:
                matched_room = r
                break
        
        if matched_room:
            rooms_found[matched_room] = geo
            continue

        # Identify Items
        # Heuristic: Check style or value
        item_type = None
        if "triangle" in style or "key" in val: item_type = "key"
        elif "ellipse" in style or "circle" in style or "fountain" in val: item_type = "fountain"
        elif "star" in style or "crypt lord" in val or "boss" in val: item_type = "boss"
        elif "square" in style or "rack" in val or "weapon" in val: item_type = "rack"

        if item_type:
            items_found.append({"type": item_type, "geo": geo})

    # Criterion 2: Rooms Creation (20 pts)
    # 20 pts / 6 rooms ~= 3.3 pts each
    rooms_score = 0
    for r in required_rooms:
        if r in rooms_found:
            rooms_score += (20.0 / len(required_rooms))
    score += rooms_score
    feedback.append(f"Rooms found: {len(rooms_found)}/{len(required_rooms)}.")

    # Criterion 3: Connectivity (20 pts)
    # Since checking explicit edge connectivity in XML can be flaky if agent just draws lines near boxes,
    # we will give points if we have enough edges total compared to rooms, 
    # OR if we strictly parse source/target attributes.
    # Let's count simple edges for robustness.
    edge_count = 0
    for cell in cells:
        if cell.get("edge") == "1":
            edge_count += 1
    
    if edge_count >= 5: # Minimal spanning tree for 6 rooms is 5 edges
        score += 20
        feedback.append("Sufficient connectivity detected.")
    elif edge_count > 0:
        score += 10
        feedback.append("Partial connectivity detected.")
    else:
        feedback.append("No connections found.")

    # Criterion 4: Spatial Layout (25 pts)
    # Check rules: e.g. "Armory" (source) WEST OF "Grand Hall" (target)
    # West: source.cx < target.cx
    # North: source.cy < target.cy (screen coords: 0 is top, so smaller Y is North)
    spatial_score = 0
    spatial_total = len(spatial_rules)
    
    for rule in spatial_rules:
        src = rule["source"]
        tgt = rule["target"]
        rel = rule["relation"]
        
        if src in rooms_found and tgt in rooms_found:
            s_geo = rooms_found[src]
            t_geo = rooms_found[tgt]
            
            passed = False
            if rel == "north":
                if s_geo["cy"] < t_geo["cy"]: passed = True # Smaller Y is higher/North
            elif rel == "south":
                if s_geo["cy"] > t_geo["cy"]: passed = True
            elif rel == "west":
                if s_geo["cx"] < t_geo["cx"]: passed = True
            elif rel == "east":
                if s_geo["cx"] > t_geo["cx"]: passed = True
            
            if passed:
                spatial_score += (25.0 / spatial_total)
    
    score += spatial_score
    feedback.append(f"Spatial layout score: {spatial_score:.1f}/25.")

    # Criterion 5: Item Containment (25 pts)
    # Check if center of item is inside box of room
    containment_score = 0
    containment_total = len(containment_rules)

    for rule in containment_rules:
        room_name = rule["room"]
        itype = rule["item_type"]
        
        if room_name not in rooms_found:
            continue
            
        r_geo = rooms_found[room_name]
        
        # Check if ANY item of this type is inside this room
        found_in_room = False
        for item in items_found:
            if item["type"] == itype:
                # Point in Rect check
                ix, iy = item["geo"]["cx"], item["geo"]["cy"]
                rx, ry, rw, rh = r_geo["x"], r_geo["y"], r_geo["w"], r_geo["h"]
                
                if (rx <= ix <= rx + rw) and (ry <= iy <= ry + rh):
                    found_in_room = True
                    break
        
        if found_in_room:
            containment_score += (25.0 / containment_total)

    score += containment_score
    feedback.append(f"Item placement score: {containment_score:.1f}/25.")

    # Pass Threshold
    passed = score >= 65
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }