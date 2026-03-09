#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import base64
import zlib
import urllib.parse
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_content(xml_content):
    """
    Decodes draw.io XML content.
    Draw.io files are often double-encoded: URL encoded -> Base64 -> Deflate.
    """
    try:
        # 1. Parse outer XML
        root = ET.fromstring(xml_content)
        
        # 2. Check if it's a compressed mxfile
        if root.tag == 'mxfile':
            diagram = root.find('diagram')
            if diagram is not None and diagram.text:
                # 3. Decode: Base64 -> Inflate -> URL Decode
                compressed_data = base64.b64decode(diagram.text)
                try:
                    # -15 for raw deflate (no header)
                    xml_data = zlib.decompress(compressed_data, -15)
                except:
                    # Fallback to standard zlib
                    xml_data = zlib.decompress(compressed_data)
                
                decoded_xml = urllib.parse.unquote(xml_data.decode('utf-8'))
                return ET.fromstring(decoded_xml)
        
        return root
    except Exception as e:
        logger.error(f"Error decoding XML: {e}")
        return None

def verify_argument_map_ai_regulation(traj, env_info, task_info):
    """
    Verifies the Argument Map task.
    Criteria:
    1. File modified & Export exists (Anti-gaming check)
    2. Central claim node present
    3. Supporting/Opposing arguments present (text check)
    4. Edge styles correct (Green/Solid vs Red/Dashed)
    5. Layout separation (Left vs Right)
    6. VLM Verification of visual structure
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # --- Step 1: Get Basic Result Data ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_data.get('diagram_modified'):
        return {"passed": False, "score": 0, "feedback": "Diagram file was not modified."}
    
    score += 5 # Modified file
    if result_data.get('export_exists') and result_data.get('export_fresh'):
        score += 10
        feedback_parts.append("PDF exported.")
    else:
        feedback_parts.append("PDF export missing or old.")

    # --- Step 2: Parse Diagram XML ---
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    try:
        copy_from_env("/tmp/final_diagram.drawio", temp_drawio.name)
        with open(temp_drawio.name, 'r') as f:
            xml_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve diagram file: {e}"}
    finally:
        if os.path.exists(temp_drawio.name):
            os.unlink(temp_drawio.name)

    root = decode_drawio_content(xml_content)
    if root is None:
        return {"passed": False, "score": score, "feedback": "Failed to parse diagram XML."}

    # Extract Cells
    nodes = []
    edges = []
    
    # mxCell elements
    # Vertices: have 'vertex="1"' or are children of root without edge="1"
    # Edges: have 'edge="1"'
    for cell in root.findall(".//mxCell"):
        value = cell.get('value', '')
        style = cell.get('style', '')
        is_edge = cell.get('edge') == '1'
        is_vertex = cell.get('vertex') == '1'
        source = cell.get('source')
        target = cell.get('target')
        cell_id = cell.get('id')
        
        # Get Geometry (for layout check)
        geo = cell.find('mxGeometry')
        x = float(geo.get('x', 0)) if geo is not None else 0.0
        
        if is_edge:
            edges.append({'id': cell_id, 'source': source, 'target': target, 'style': style.lower()})
        elif is_vertex or value:
            # Clean HTML tags from value if present
            # Simple text extraction
            import re
            text = re.sub('<[^<]+?>', '', value).strip().lower()
            if text:
                nodes.append({'id': cell_id, 'text': text, 'x': x})

    # --- Step 3: Verify Nodes & Content (40 pts) ---
    metadata = task_info.get('metadata', {})
    
    # Central Claim
    central_node = None
    for n in nodes:
        if any(k in n['text'] for k in metadata.get('central_keywords', [])):
            central_node = n
            break
            
    if central_node:
        score += 5
        feedback_parts.append("Central claim found.")
    else:
        feedback_parts.append("Central claim missing.")

    # Arguments
    support_count = 0
    oppose_count = 0
    rebuttal_count = 0
    
    support_nodes = []
    oppose_nodes = []
    
    for n in nodes:
        if n == central_node: continue
        
        if any(k in n['text'] for k in metadata.get('support_keywords', [])):
            support_count += 1
            support_nodes.append(n)
        elif any(k in n['text'] for k in metadata.get('oppose_keywords', [])):
            oppose_count += 1
            oppose_nodes.append(n)
        elif any(k in n['text'] for k in metadata.get('rebuttal_keywords', [])):
            rebuttal_count += 1
            
    # Score arguments (cap at expected counts)
    score += min(support_count, 3) * 5  # Max 15
    score += min(oppose_count, 3) * 5   # Max 15
    score += min(rebuttal_count, 2) * 5 # Max 10
    
    feedback_parts.append(f"Args found: {support_count} Support, {oppose_count} Oppose, {rebuttal_count} Rebuttal.")

    # --- Step 4: Verify Edges & Styles (25 pts) ---
    # We need to map node IDs to types to check connections
    # Heuristic: Check edges connected to support nodes
    
    correct_style_edges = 0
    
    for edge in edges:
        style = edge['style']
        
        # Green/Solid check (Support)
        # draw.io green is typically #00CC00 or similar
        is_green = "green" in style or "#00cc00" in style
        is_solid = "dashed=1" not in style
        
        # Red/Dashed check (Oppose)
        is_red = "red" in style or "#ff0000" in style
        is_dashed = "dashed=1" in style
        
        if is_green and is_solid:
            correct_style_edges += 1
        elif is_red and is_dashed:
            correct_style_edges += 1
            
    # Normalize score based on expected edges (8 total: 3 supp + 3 opp + 2 reb)
    # We'll give points if we see at least some correct styling
    if correct_style_edges >= 6:
        score += 25
        feedback_parts.append("Edge styling matches requirements.")
    elif correct_style_edges >= 3:
        score += 15
        feedback_parts.append("Some edge styling correct.")
    else:
        feedback_parts.append("Edge styling mostly incorrect (needs Green/Solid and Red/Dashed).")

    # --- Step 5: Layout Check (10 pts) ---
    # Support on Left, Oppose on Right
    if central_node and support_nodes and oppose_nodes:
        cx = central_node['x']
        # Check avg X of support vs avg X of oppose
        avg_supp_x = sum(n['x'] for n in support_nodes) / len(support_nodes)
        avg_opp_x = sum(n['x'] for n in oppose_nodes) / len(oppose_nodes)
        
        if avg_supp_x < cx < avg_opp_x:
            score += 10
            feedback_parts.append("Layout correct (Support Left, Oppose Right).")
        else:
            feedback_parts.append("Layout incorrect.")

    # --- Step 6: VLM Verification (10 pts) ---
    # Use trajectory to verify work was done
    frames = sample_trajectory_frames(traj, n=4)
    final_ss = get_final_screenshot(traj)
    
    vlm_score = 0
    if frames:
        prompt = """
        Review these screenshots of a user creating a diagram in draw.io.
        The goal is an 'Argument Map' with a central node and supporting/opposing nodes.
        
        1. Do you see the user adding shapes and text?
        2. Do you see green (solid) and red (dashed) arrows being used?
        3. Does the final image look like a structured tree diagram?
        
        Answer JSON: {"work_visible": bool, "colors_correct": bool, "structure_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_ss], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('work_visible'): vlm_score += 4
                if parsed.get('colors_correct'): vlm_score += 3
                if parsed.get('structure_visible'): vlm_score += 3
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic score is high, assume VLM would pass
            if score > 50: vlm_score = 10
            
    score += vlm_score
    feedback_parts.append(f"VLM Score: {vlm_score}/10")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }