#!/usr/bin/env python3
"""
Verifier for configure_tabletop_physics task.

Requires adding boundingObject to 4 objects and Physics nodes with mass to 3 of them.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_node_body(text, def_name):
    """Extracts the entire block for a specific DEF node, respecting brace nesting."""
    start_idx = text.find(f"DEF {def_name} Solid")
    if start_idx == -1:
        return None
    
    brace_idx = text.find("{", start_idx)
    if brace_idx == -1:
        return None
        
    depth = 1
    i = brace_idx + 1
    while i < len(text) and depth > 0:
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
        i += 1
        
    if depth == 0:
        return text[start_idx:i]
    return None

def has_bounding_object(node_text):
    """Checks if boundingObject field is assigned a value (not NULL)."""
    return bool(re.search(r'boundingObject\s+(?!NULL)[A-Za-z]', node_text))

def has_physics_with_mass(node_text):
    """Checks if physics field is assigned a Physics node with a mass > 0."""
    if not re.search(r'physics\s+Physics\s*\{', node_text):
        return False
    mass_match = re.search(r'mass\s+([\d.]+)', node_text)
    if mass_match and float(mass_match.group(1)) > 0:
        return True
    return False

def verify_configure_tabletop_physics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Desktop/physics_configured.wbt')

    # 1. Retrieve the exported JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read exported JSON: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check file existence and anti-gaming modification times
    if not result.get('file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file {expected_output} not found. You must save the world to the specified path."
        }
        
    start_time = result.get('task_start_timestamp', 0)
    mtime = result.get('file_mtime', 0)
    if mtime > 0 and start_time > 0 and mtime < start_time:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was modified before the task started. Anti-gaming check failed."
        }

    # 3. Retrieve the target .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_content = ""
    try:
        copy_from_env(expected_output, wbt_file.name)
        with open(wbt_file.name, 'r', encoding='utf-8', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.error(f"Failed to copy wbt file: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve the saved world file."}
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)
            
    # File validity check
    if "#VRML_SIM" not in wbt_content:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Saved file is not a valid Webots world (missing #VRML_SIM header)."
        }

    score = 10
    feedback = ["File saved correctly (+10)."]
    
    # 4. Programmatic Verification of Physics Fields
    
    # TABLE Check
    table_node = extract_node_body(wbt_content, "TABLE")
    if table_node:
        if has_bounding_object(table_node):
            score += 15
            feedback.append("TABLE has boundingObject (+15).")
        else:
            feedback.append("TABLE is missing boundingObject.")
    else:
        feedback.append("DEF TABLE Solid node not found.")

    # RED_BOX Check
    red_box_node = extract_node_body(wbt_content, "RED_BOX")
    if red_box_node:
        if has_bounding_object(red_box_node):
            score += 10
            feedback.append("RED_BOX has boundingObject (+10).")
        else:
            feedback.append("RED_BOX is missing boundingObject.")
            
        if has_physics_with_mass(red_box_node):
            score += 15
            feedback.append("RED_BOX has Physics with mass > 0 (+15).")
        else:
            feedback.append("RED_BOX is missing Physics node or positive mass.")
    else:
        feedback.append("DEF RED_BOX Solid node not found.")

    # BLUE_SPHERE Check
    blue_sphere_node = extract_node_body(wbt_content, "BLUE_SPHERE")
    if blue_sphere_node:
        if has_bounding_object(blue_sphere_node):
            score += 10
            feedback.append("BLUE_SPHERE has boundingObject (+10).")
        else:
            feedback.append("BLUE_SPHERE is missing boundingObject.")
            
        if has_physics_with_mass(blue_sphere_node):
            score += 15
            feedback.append("BLUE_SPHERE has Physics with mass > 0 (+15).")
        else:
            feedback.append("BLUE_SPHERE is missing Physics node or positive mass.")
    else:
        feedback.append("DEF BLUE_SPHERE Solid node not found.")
        
    # GREEN_CYLINDER Check
    green_cylinder_node = extract_node_body(wbt_content, "GREEN_CYLINDER")
    if green_cylinder_node:
        if has_bounding_object(green_cylinder_node):
            score += 10
            feedback.append("GREEN_CYLINDER has boundingObject (+10).")
        else:
            feedback.append("GREEN_CYLINDER is missing boundingObject.")
            
        if has_physics_with_mass(green_cylinder_node):
            score += 15
            feedback.append("GREEN_CYLINDER has Physics with mass > 0 (+15).")
        else:
            feedback.append("GREEN_CYLINDER is missing Physics node or positive mass.")
    else:
        feedback.append("DEF GREEN_CYLINDER Solid node not found.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }