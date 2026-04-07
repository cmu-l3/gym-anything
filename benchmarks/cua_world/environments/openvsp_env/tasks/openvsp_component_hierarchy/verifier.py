#!/usr/bin/env python3
"""
Verifier for openvsp_component_hierarchy task.

Evaluates the saved .vsp3 XML file for proper parent-child links and translations.
Points:
  - File exists & modified during task: 10 pts
  - Wing Parent correct: 15 pts
  - V-Tail Parent correct: 15 pts
  - H-Tail Parent correct: 20 pts
  - Wing X Location: 10 pts
  - V-Tail X Location: 10 pts
  - H-Tail X and Z Location: 20 pts

Pass threshold: 70 points.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET

def get_geom_info(root, name_substring):
    """Finds a Geom by substring in its Name and extracts its ID, ParentID, and XForm locations."""
    for geom in root.findall('.//Geom'):
        name_node = geom.find('Name')
        if name_node is not None and name_substring.lower() in name_node.text.lower():
            geom_id = geom.find('ID').text.strip() if geom.find('ID') is not None else None
            
            # ParentID can be empty if unlinked
            parent_id_node = geom.find('ParentID')
            parent_id = parent_id_node.text.strip() if (parent_id_node is not None and parent_id_node.text) else ""
            
            x_loc, z_loc = 0.0, 0.0
            for pc in geom.findall('.//ParmContainer'):
                pc_name = pc.find('Name')
                if pc_name is not None and pc_name.text == 'XForm':
                    x_node = pc.find('X_Location')
                    if x_node is not None:
                        x_loc = float(x_node.get('Value', '0.0'))
                    z_node = pc.find('Z_Location')
                    if z_node is not None:
                        z_loc = float(z_node.get('Value', '0.0'))
            
            return {
                'id': geom_id,
                'parent_id': parent_id,
                'x': x_loc,
                'z': z_loc
            }
    return None

def verify_openvsp_component_hierarchy(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_component_hierarchy_result.json"
    )

    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    local_tmp.close()
    
    try:
        env_info["copy_from_env"](result_file, local_tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}"
        }

    with open(local_tmp.name, "r") as f:
        data = json.load(f)
    os.unlink(local_tmp.name)

    score = 0
    feedback_parts = []

    # Check 1: File Exists & Timing (10 pts)
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "assembled_jet.vsp3 not found. The model was not saved."
        }
        
    mtime = data.get("file_mtime", 0)
    task_start = data.get("task_start", 0)
    if mtime >= task_start:
        score += 10
        feedback_parts.append("File successfully saved during task (+10).")
    else:
        feedback_parts.append("File modification time is older than task start. (+0).")

    # Parse XML
    content = data.get("file_content", "").replace("\\n", "\n").replace("\\t", "\t")
    try:
        root = ET.fromstring(content)
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"File is not valid XML: {e} | " + " | ".join(feedback_parts)
        }

    # Extract component data
    fuselage = get_geom_info(root, "fuselage")
    wing = get_geom_info(root, "wing")
    vtail = get_geom_info(root, "vertical")
    htail = get_geom_info(root, "horizontal")

    if not all([fuselage, wing, vtail, htail]):
        feedback_parts.append("Missing one or more required components (Fuselage, Wing, Vertical, Horizontal).")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Tolerances
    tol = task_info.get("metadata", {}).get("tolerance", 0.5)

    # Check Wing Hierarchy & Position
    if wing["parent_id"] == fuselage["id"] and fuselage["id"] is not None:
        score += 15
        feedback_parts.append("Wing parent correctly set to Fuselage (+15).")
    else:
        feedback_parts.append("Wing parent is NOT Fuselage (+0).")

    if abs(wing["x"] - task_info["metadata"]["expected_wing_x"]) <= tol:
        score += 10
        feedback_parts.append(f"Wing X Location correct ({wing['x']} m) (+10).")
    else:
        feedback_parts.append(f"Wing X Location incorrect ({wing['x']} m) (+0).")

    # Check V-Tail Hierarchy & Position
    if vtail["parent_id"] == fuselage["id"] and fuselage["id"] is not None:
        score += 15
        feedback_parts.append("Vertical Tail parent correctly set to Fuselage (+15).")
    else:
        feedback_parts.append("Vertical Tail parent is NOT Fuselage (+0).")

    if abs(vtail["x"] - task_info["metadata"]["expected_vtail_x"]) <= tol:
        score += 10
        feedback_parts.append(f"Vertical Tail X Location correct ({vtail['x']} m) (+10).")
    else:
        feedback_parts.append(f"Vertical Tail X Location incorrect ({vtail['x']} m) (+0).")

    # Check H-Tail Hierarchy & Position
    if htail["parent_id"] == vtail["id"] and vtail["id"] is not None:
        score += 20
        feedback_parts.append("Horizontal Tail parent correctly set to Vertical Tail (+20).")
    else:
        feedback_parts.append("Horizontal Tail parent is NOT Vertical Tail (+0).")

    htail_x_correct = abs(htail["x"] - task_info["metadata"]["expected_htail_x"]) <= tol
    htail_z_correct = abs(htail["z"] - task_info["metadata"]["expected_htail_z"]) <= tol
    
    if htail_x_correct and htail_z_correct:
        score += 20
        feedback_parts.append(f"Horizontal Tail X/Z Locations correct ({htail['x']}, {htail['z']} m) (+20).")
    elif htail_x_correct or htail_z_correct:
        score += 10
        feedback_parts.append(f"Horizontal Tail Location partially correct ({htail['x']}, {htail['z']} m) (+10).")
    else:
        feedback_parts.append(f"Horizontal Tail Location incorrect ({htail['x']}, {htail['z']} m) (+0).")

    # Final Evaluation
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }