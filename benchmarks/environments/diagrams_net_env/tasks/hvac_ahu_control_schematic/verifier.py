#!/usr/bin/env python3
"""
Verifier for HVAC AHU Control Schematic task.
"""

import json
import os
import tempfile
import logging
import zlib
import base64
import urllib.parse
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_xml(content):
    """
    Decodes a draw.io file content.
    Draw.io files are often:
    1. Plain XML (uncompressed)
    2. URL-encoded + Base64 + Deflate compressed (inside <diagram> tag)
    """
    try:
        # Check if it's a standard mxfile
        if b'<mxfile' not in content:
            return None
        
        root = ET.fromstring(content)
        diagram_node = root.find('diagram')
        
        if diagram_node is None:
            return content.decode('utf-8', errors='ignore')
            
        # If there is a diagram node, check if it's compressed
        if diagram_node.text and len(diagram_node.text.strip()) > 0:
            try:
                # Attempt to decode: Base64 -> Inflate (no header)
                compressed_data = base64.b64decode(diagram_node.text)
                xml_data = zlib.decompress(compressed_data, -15) # -15 for raw deflate
                decoded_xml = urllib.parse.unquote(xml_data.decode('utf-8'))
                return decoded_xml
            except Exception as e:
                logger.info(f"Could not decompress diagram node: {e}")
                # It might be uncompressed text already?
                return diagram_node.text
        
        # Fallback: return raw content as string
        return content.decode('utf-8', errors='ignore')
        
    except Exception as e:
        logger.error(f"Error parsing drawio XML: {e}")
        return content.decode('utf-8', errors='ignore')

def verify_hvac_schematic(traj, env_info, task_info):
    """
    Verifies the HVAC schematic task.
    
    Criteria:
    1. Source file exists and was modified (anti-gaming).
    2. PDF export exists.
    3. Content Check:
       - Required components (SF-1, CC-1, etc.)
       - Required sensors (MAT, SAT, etc.)
       - "Dashed" lines present (indicating control logic).
    4. VLM Check: 
       - Visual confirmation of schematic structure.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    score = 0
    feedback = []
    
    # 1. Load basic result metadata
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, "r") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Basic Checks
    if not result_data.get("source_exists", False):
        return {"passed": False, "score": 0, "feedback": "Source .drawio file not found."}
        
    score += 10 # File created
    feedback.append("Source file created.")
    
    if result_data.get("file_modified", False):
        score += 10
        feedback.append("File modified during task.")
    else:
        feedback.append("WARNING: File timestamp suggests it wasn't modified during task.")
        
    if result_data.get("pdf_exists", False):
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # 2. Content Analysis (Parsing the drawio file)
    # We copy the actual .drawio file out to parse it
    content_text = ""
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix=".drawio")
    try:
        copy_from_env("/home/ga/Diagrams/AHU-1_Schematic.drawio", temp_drawio.name)
        with open(temp_drawio.name, "rb") as f:
            raw_content = f.read()
            content_text = decode_drawio_xml(raw_content)
    except Exception as e:
        feedback.append(f"Failed to parse source file: {e}")
    finally:
        if os.path.exists(temp_drawio.name):
            os.unlink(temp_drawio.name)
            
    if content_text:
        content_lower = content_text.lower()
        
        # Check Components (30 pts)
        components = ["sf-1", "cc-1", "hc-1", "pf-1", "ff-1", "oad-1", "rad-1"]
        comps_found = 0
        for comp in components:
            if comp.lower() in content_lower:
                comps_found += 1
        
        comp_score = min(30, int((comps_found / len(components)) * 30))
        score += comp_score
        feedback.append(f"Components found: {comps_found}/{len(components)} ({comp_score} pts)")

        # Check Sensors (20 pts)
        sensors = ["sat", "mat", "rat", "dsp"]
        sens_found = 0
        for sens in sensors:
            if sens.lower() in content_lower:
                sens_found += 1
        
        sens_score = min(20, int((sens_found / len(sensors)) * 20))
        score += sens_score
        feedback.append(f"Sensors found: {sens_found}/{len(sensors)} ({sens_score} pts)")
        
        # Check Control Logic (Dashed Lines) (10 pts)
        # In draw.io XML, dashed lines usually have style="...dashed=1..."
        if "dashed=1" in content_lower:
            score += 10
            feedback.append("Dashed control lines detected.")
        else:
            feedback.append("No dashed control lines found.")
            
    # 3. VLM Verification (20 pts)
    # Check if trajectory looks like schematic editing
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        if final_shot:
            frames.append(final_shot)
            
        prompt = """
        You are verifying a task to create an HVAC schematic diagram.
        Look at these screenshots.
        1. Do you see a technical diagram with connected shapes?
        2. Are there recognizable components like fans (circles/squares with blades), coils (zig-zags), or dampers?
        3. Is there text labeling components like 'SF-1' or 'SAT'?
        4. Are there distinct line styles (solid vs dashed)?
        
        Return JSON: {"is_schematic": bool, "has_labels": bool, "has_line_styles": bool}
        """
        
        vlm_result = query_vlm(prompt=prompt, images=frames)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("is_schematic"):
                vlm_score += 10
            if parsed.get("has_labels"):
                vlm_score += 5
            if parsed.get("has_line_styles"):
                vlm_score += 5
            feedback.append(f"VLM verification passed: {parsed}")
        else:
            feedback.append("VLM verification failed to run.")
            
    except Exception as e:
        feedback.append(f"VLM error: {e}")
        # Fallback points if programmatic checks were very strong
        if score > 60:
            vlm_score = 10 
            
    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }