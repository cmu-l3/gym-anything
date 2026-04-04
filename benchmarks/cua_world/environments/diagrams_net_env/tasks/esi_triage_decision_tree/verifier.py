#!/usr/bin/env python3
"""
Verifier for ESI Triage Decision Tree task.
Checks:
1. Diagram structure (nodes added, TODO removed).
2. Content (Text labels for ESI levels, decisions).
3. Colors (Hex codes for acuity levels).
4. Export existence.
5. VLM trajectory verification (Process check).
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
import base64
import zlib
import re
from urllib.parse import unquote

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio(xml_content):
    """
    Decodes the compressed XML format often used by draw.io.
    """
    try:
        # Check if standard XML first
        if "<mxGraphModel" in xml_content and not "<diagram" in xml_content:
            return xml_content
            
        root = ET.fromstring(xml_content)
        if root.tag == 'mxfile':
            diagram_node = root.find('diagram')
            if diagram_node is not None and diagram_node.text:
                # Decode: Base64 -> Inflate (zlib -15) -> URL Decode
                # Note: draw.io often does Raw Deflate.
                data = base64.b64decode(diagram_node.text)
                try:
                    xml_str = zlib.decompress(data, -15).decode('utf-8')
                    return urllib.parse.unquote(xml_str)
                except Exception as e:
                    # sometimes it's just base64?
                    return data.decode('utf-8')
        return xml_content
    except Exception as e:
        logger.error(f"Error decoding XML: {e}")
        return xml_content

def verify_esi_triage_tree(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Fetch Data
    files = {
        'json': ('/tmp/task_result.json', 'json'),
        'drawio': ('/home/ga/Diagrams/esi_triage_tree.drawio', 'xml')
    }
    
    data = {}
    temp_files = []
    
    try:
        for key, (path, fmt) in files.items():
            t = tempfile.NamedTemporaryFile(delete=False)
            t.close()
            temp_files.append(t.name)
            try:
                copy_from_env(path, t.name)
                with open(t.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    if fmt == 'json':
                        data[key] = json.loads(content)
                    else:
                        data[key] = content
            except Exception as e:
                logger.warning(f"Could not load {key}: {e}")
                data[key] = None

    finally:
        for t in temp_files:
            if os.path.exists(t):
                os.unlink(t)

    result_json = data.get('json', {})
    raw_xml = data.get('drawio', "")
    
    # Scoring Config
    score = 0
    feedback = []
    
    # --- CRITERION 1: File Modification & Exports (15 pts) ---
    if result_json.get('diagram_modified'):
        score += 5
        feedback.append("Diagram file modified (+5)")
    else:
        feedback.append("Diagram file NOT modified (0)")
        
    if result_json.get('png_exported'):
        score += 5
        feedback.append("PNG export found (+5)")
    else:
        feedback.append("PNG export missing (0)")

    if result_json.get('svg_exported'):
        score += 5
        feedback.append("SVG export found (+5)")
    else:
        feedback.append("SVG export missing (0)")

    # --- CRITERION 2: XML Content Analysis (50 pts) ---
    # We parse the XML to check shapes and text
    
    if raw_xml:
        decoded_xml = decode_drawio(raw_xml)
        
        # Simple string matching is robust for draw.io XML soup
        # Normalizing text
        lower_xml = decoded_xml.lower()
        
        # 2a. TODO Removed (5 pts)
        if "todo" not in lower_xml:
            score += 5
            feedback.append("TODO note removed (+5)")
        else:
            feedback.append("TODO note still present (0)")

        # 2b. Decision C Present (Resource) (10 pts)
        if "resource" in lower_xml or "how many" in lower_xml:
            score += 10
            feedback.append("Decision C (Resources) found (+10)")
        else:
            feedback.append("Decision C (Resources) missing (0)")

        # 2c. Decision D Present (Vitals/Danger) (10 pts)
        if "vital" in lower_xml or "danger" in lower_xml:
            score += 10
            feedback.append("Decision D (Vitals) found (+10)")
        else:
            feedback.append("Decision D (Vitals) missing (0)")
            
        # 2d. ESI Levels 3, 4, 5 (15 pts)
        # Check for presence of level text
        levels_found = 0
        if "level 3" in lower_xml or "urgent" in lower_xml: levels_found += 1
        if "level 4" in lower_xml or "less urgent" in lower_xml: levels_found += 1
        if "level 5" in lower_xml or "non-urgent" in lower_xml: levels_found += 1
        
        score += (levels_found * 5)
        feedback.append(f"Found {levels_found}/3 new ESI levels (+{levels_found*5})")
    else:
        feedback.append("Could not parse diagram XML (0)")

    # --- CRITERION 3: Color Coding (15 pts) ---
    # Check for color hex codes in style attributes
    # Red: #FF0000, Orange: #FF8C00 (or close approximations)
    # Blue: #0000FF, Green: #00B050, Yellow: #FFD700
    
    colors_found = set()
    if raw_xml:
        # Extract all fillColors
        fill_matches = re.findall(r'fillColor=(#[A-Fa-f0-9]{6})', decoded_xml)
        colors_found = set([c.upper() for c in fill_matches])
        
        # We need at least 5 distinct colors (ignoring white/grey/black background colors)
        # Known background/decision colors: #F5F5F5, #FFF2CC, #FFFFFF
        meaningful_colors = [c for c in colors_found if c not in ['#F5F5F5', '#FFF2CC', '#FFFFFF', '#F8CECC', '#000000']]
        
        if len(meaningful_colors) >= 4:
            score += 15
            feedback.append(f"Color coding detected ({len(meaningful_colors)} distinct colors) (+15)")
        elif len(meaningful_colors) >= 2:
            score += 7
            feedback.append(f"Partial color coding detected ({len(meaningful_colors)} distinct colors) (+7)")
        else:
            feedback.append("Insufficient color coding (0)")

    # --- CRITERION 4: VLM Trajectory Verification (20 pts) ---
    # Use the VLM to verify the "Feedback Loop" (Upgrade arrow) and general structure
    # This is hard to regex because it's a specific topology (D -> Yes -> Level 2)
    
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        You are verifying a flowchart/decision tree diagram task.
        Look at the sequence of screenshots.
        1. Does the diagram show a tree structure expanding downwards?
        2. Are there diamond shapes (decisions) and colored rounded rectangles (results)?
        3. Is there an arrow pointing BACKWARDS/UPWARDS (a feedback loop) from the bottom right area back to an upper level? This represents an 'Upgrade' path.
        
        Return JSON: {"tree_structure_visible": bool, "feedback_loop_visible": bool, "colors_visible": bool}
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        vlm_score = 0
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('tree_structure_visible'): vlm_score += 5
            if parsed.get('colors_visible'): vlm_score += 5
            if parsed.get('feedback_loop_visible'): vlm_score += 10
            
            score += vlm_score
            feedback.append(f"VLM verification: {vlm_score}/20 pts (Loop: {parsed.get('feedback_loop_visible')})")
        else:
            feedback.append("VLM verification failed (0)")
            # Fallback points if XML looks really good
            if score >= 60:
                score += 10
                feedback.append("Fallback VLM points awarded based on strong XML evidence (+10)")
    else:
         feedback.append("No trajectory frames available for VLM (0)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "\n".join(feedback)
    }