#!/usr/bin/env python3
"""
Verifier for configure_warehouse_lighting task.

Checks:
1. File exists at /home/ga/Desktop/warehouse_lighting.wbt (10 pts)
2. DirectionalLight modified correctly (intensity 0.4, castShadows TRUE, dir Y < 0) (35 pts)
3. Background luminosity updated to 1.2 (15 pts)
4. Two PointLights added with appropriate values (40 pts)
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_node_content(node_type, text):
    """
    Extracts the block of text inside a Webots node.
    Assumes these basic lighting nodes don't contain nested braces.
    """
    pattern = re.compile(node_type + r'\s*\{([^}]*)\}', re.DOTALL)
    return pattern.findall(text)

def verify_configure_warehouse_lighting(traj, env_info, task_info):
    """
    Verify the warehouse lighting configuration was successfully applied.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/warehouse_lighting.wbt')
    
    score = 0
    feedback_parts = []
    
    # 1. Check basic export results for anti-gaming timestamps
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/task_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
        
        if not export_result.get("file_created_during_task", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file was not created during the task session. Did you save it properly?"
            }
    except Exception as e:
        logger.warning(f"Could not check export results: {e}")

    # 2. Extract and parse the .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    # --- Criterion: File exists & valid size (10 pts) ---
    if not wbt_content or len(wbt_content) < 300:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found or invalid at {output_path}. Use File > Save World As."
        }
    
    score += 10
    feedback_parts.append("File exists")

    # --- Criterion: DirectionalLight settings (35 pts) ---
    dir_lights = extract_node_content('DirectionalLight', wbt_content)
    if dir_lights:
        dl_content = dir_lights[0]
        
        # Intensity (15 pts)
        intensity_match = re.search(r'intensity\s+([\d.]+)', dl_content)
        if intensity_match:
            intensity = float(intensity_match.group(1))
            if 0.3 <= intensity <= 0.5:
                score += 15
                feedback_parts.append("DirectionalLight intensity correct")
            else:
                feedback_parts.append(f"DirectionalLight intensity wrong ({intensity})")
        else:
            feedback_parts.append("DirectionalLight intensity not found")
            
        # castShadows (10 pts)
        if "castShadows TRUE" in dl_content:
            score += 10
            feedback_parts.append("castShadows enabled")
        else:
            feedback_parts.append("castShadows not TRUE")
            
        # Direction Y is negative (10 pts)
        dir_match = re.search(r'direction\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)', dl_content)
        if dir_match:
            y_dir = float(dir_match.group(2))
            if y_dir < 0:
                score += 10
                feedback_parts.append("DirectionalLight pointing downwards")
            else:
                feedback_parts.append("DirectionalLight not pointing downwards")
        else:
            feedback_parts.append("DirectionalLight direction not found")
    else:
        feedback_parts.append("DirectionalLight not found in world")

    # --- Criterion: Background luminosity (15 pts) ---
    bgs = extract_node_content('Background', wbt_content)
    if bgs:
        bg_content = bgs[0]
        lum_match = re.search(r'luminosity\s+([\d.]+)', bg_content)
        if lum_match:
            lum = float(lum_match.group(1))
            if 1.1 <= lum <= 1.5:
                score += 15
                feedback_parts.append("Background luminosity correct")
            else:
                feedback_parts.append(f"Background luminosity wrong ({lum})")
        else:
            feedback_parts.append("Background luminosity not found")
    else:
        feedback_parts.append("Background node not found")

    # --- Criterion: PointLights added and configured (40 pts) ---
    point_lights = extract_node_content('PointLight', wbt_content)
    
    if len(point_lights) >= 2:
        score += 20
        feedback_parts.append(f"Found {len(point_lights)} PointLight nodes")
        
        valid_intensity = False
        valid_height = False
        
        for pl in point_lights:
            # Check intensity
            i_match = re.search(r'intensity\s+([\d.]+)', pl)
            if i_match and 0.4 <= float(i_match.group(1)) <= 0.8:
                valid_intensity = True
                
            # Check height (Y value of location)
            loc_match = re.search(r'location\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)', pl)
            if loc_match and float(loc_match.group(2)) >= 3.0:
                valid_height = True
                
        if valid_intensity:
            score += 10
            feedback_parts.append("PointLight intensity in correct range")
        else:
            feedback_parts.append("PointLight intensity incorrect")
            
        if valid_height:
            score += 10
            feedback_parts.append("PointLight positioned at correct height")
        else:
            feedback_parts.append("PointLight height incorrect (must be overhead)")
    else:
        feedback_parts.append(f"Found only {len(point_lights)} PointLight nodes, expected 2")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }