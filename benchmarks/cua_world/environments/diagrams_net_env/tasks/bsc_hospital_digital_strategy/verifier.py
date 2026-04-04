#!/usr/bin/env python3
"""
Verifier for Balanced Scorecard Strategy Map task.
"""

import json
import tempfile
import os
import logging
import base64
import zlib
import urllib.parse
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bsc_strategy_map(traj, env_info, task_info):
    """
    Verifies the BSC strategy map task via file analysis and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve files from container
    # ------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_diagram = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    
    files_retrieved = False
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        copy_from_env("/home/ga/Diagrams/hospital_strategy_map.drawio", temp_diagram.name)
        files_retrieved = True
    except Exception as e:
        logger.error(f"Failed to copy files: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task files from environment."}

    # 2. Parse basic results
    # --------------------
    with open(temp_result.name, 'r') as f:
        stats = json.load(f)
    
    # 3. Analyze the draw.io XML content
    # --------------------------------
    xml_content = ""
    try:
        with open(temp_diagram.name, 'r') as f:
            raw_content = f.read()
            
        # Draw.io often saves as compressed XML. Try to decode.
        try:
            # Check if it's a standard mxfile
            tree = ET.fromstring(raw_content)
            if tree.tag == 'mxfile':
                diagram_node = tree.find('diagram')
                if diagram_node is not None and diagram_node.text:
                    # Compressed content
                    b64_data = base64.b64decode(diagram_node.text)
                    # deflate with -15 for raw stream (no header)
                    xml_content = zlib.decompress(b64_data, -15).decode('utf-8')
                    # Wrap in root to make it valid XML for parsing
                    xml_content = f"<root>{xml_content}</root>"
                else:
                    # Uncompressed or empty
                    xml_content = raw_content
            else:
                xml_content = raw_content
        except Exception as e:
            logger.warning(f"Compression decode failed, assuming raw XML: {e}")
            xml_content = raw_content

    except Exception as e:
        logger.error(f"Failed to read diagram file: {e}")
        xml_content = ""

    # 4. Verification Logic
    # -------------------
    score = 0
    feedback = []
    
    # Criteria A: File Stats (15 pts)
    if stats.get('diagram_modified') and stats.get('diagram_size', 0) > 1000:
        score += 15
        feedback.append("File modified and saved.")
    else:
        feedback.append("File not modified or too small.")

    # Criteria B: PDF Export (10 pts)
    if stats.get('pdf_exists') and stats.get('pdf_size', 0) > 1000:
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # Criteria C: XML Content Analysis (55 pts)
    objectives_found = 0
    edges_found = 0
    colors_found = set()
    
    expected_objectives = task_info['metadata']['expected_objectives']
    
    if xml_content:
        try:
            root = ET.fromstring(xml_content)
            
            # Count objectives (Vertex with value matching expected text)
            # Use lower case fuzzy match
            cells = root.findall(".//mxCell")
            found_objective_names = []
            
            for cell in cells:
                value = cell.get('value', '')
                style = cell.get('style', '')
                vertex = cell.get('vertex')
                edge = cell.get('edge')
                
                # Check for objectives
                if vertex == '1' and value:
                    val_lower = value.lower()
                    for obj in expected_objectives:
                        # Match significant part of string
                        if obj.lower() in val_lower:
                            if obj not in found_objective_names:
                                found_objective_names.append(obj)
                                objectives_found += 1
                                
                                # Check color
                                # fillColors in style string like "fillColor=#FFD700;"
                                if 'fillColor' in style:
                                    colors_found.add(style.split('fillColor=')[1].split(';')[0])
                
                # Check for edges
                if edge == '1':
                    source = cell.get('source')
                    target = cell.get('target')
                    if source and target:
                        edges_found += 1

        except Exception as e:
            feedback.append(f"Error parsing XML content: {e}")

    # Scoring content
    # Objectives: 2 pts each, max 30
    obj_score = min(30, objectives_found * 2)
    score += obj_score
    feedback.append(f"Found {objectives_found}/16 objectives.")
    
    # Edges: 1 pt each, max 15
    edge_score = min(15, edges_found)
    score += edge_score
    feedback.append(f"Found {edges_found} connections.")
    
    # Colors: 10 pts if at least 3 distinct colors used
    if len(colors_found) >= 3:
        score += 10
        feedback.append(f"Color coding applied ({len(colors_found)} colors).")
    else:
        feedback.append(f"Color coding insufficient ({len(colors_found)} colors).")

    # Criteria D: VLM Trajectory Verification (20 pts)
    # ---------------------------------------------
    # Use VLM to ensure they didn't just paste a picture or do nothing
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a user working in Diagrams.net (draw.io).
        Task: Create a strategy map with labeled shapes and arrows in swimlanes.
        
        Check for:
        1. Are there multiple shapes visible inside the horizontal swimlanes?
        2. Are there arrows connecting these shapes?
        3. Did the user actively edit the diagram (not just a static image)?
        
        Answer with JSON: {"valid_workflow": boolean, "shapes_visible": boolean, "reason": "string"}
        """
        
        result = query_vlm(images=frames + [final], prompt=prompt)
        
        if result and result.get('parsed', {}).get('valid_workflow'):
            vlm_score = 20
            feedback.append("VLM verified valid workflow.")
        else:
            feedback.append("VLM could not verify valid workflow.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if XML score is high, assume pass
        if score > 50:
            vlm_score = 20
            feedback.append("VLM skipped, trusting XML analysis.")

    score += vlm_score

    # Cleanup
    os.unlink(temp_result.name)
    os.unlink(temp_diagram.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }