#!/usr/bin/env python3
"""
Verifier for the annotate_waypoints_field_notes task.

It utilizes BOTH programmatic file verification (GPX XML parsing) 
and VLM trajectory verification to ensure robust anti-gaming evaluation.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def strip_namespace(tag):
    """Remove GPX namespace from XML tag for easier searching."""
    return tag.split('}')[-1] if '}' in tag else tag

def query_trajectory_vlm(traj):
    """Use VLM to check if the agent interacted with the properties and export dialogs."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """
        Review these screenshots from a user's session in Garmin BaseCamp.
        Check for two specific workflows:
        1. Did the user open a Waypoint Properties window and type text into the Notes/Comment/Description text field?
        2. Did the user open a File Export or Save dialog to save a .gpx file?
        
        Respond ONLY with a JSON object:
        {
            "properties_dialog_used": true/false,
            "export_dialog_used": true/false
        }
        """
        
        response = query_vlm(images=images, prompt=prompt)
        if response and response.get("success"):
            return response.get("parsed", {})
    except ImportError:
        logger.warning("VLM utilities not available.")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        
    return {"properties_dialog_used": False, "export_dialog_used": False}

def verify_annotate_waypoints(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    alpha_1 = metadata.get('alpha_string_1', 'Field station alpha')
    alpha_2 = metadata.get('alpha_string_2', 'Soil sample FS-001')
    beta_1 = metadata.get('beta_string_1', 'Field station beta')
    beta_2 = metadata.get('beta_string_2', 'IMG_2847')
    bounds = metadata.get('bounds', {})

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the JSON execution metadata
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/workspace/output/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read execution result: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    # 2. GPX File Extraction
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Target GPX file was not created"}
    
    gpx_file = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("/workspace/output/annotated_fells.gpx", gpx_file.name)
        tree = ET.parse(gpx_file.name)
        root = tree.getroot()
        score += 10
        feedback_parts.append("Valid GPX file found")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"GPX parse error: {e}"}
    
    # 3. GPX Content Parsing
    wpts = []
    trks = []
    
    for child in root.iter():
        tag = strip_namespace(child.tag)
        if tag == 'wpt':
            wpts.append(child)
        elif tag == 'trk':
            trks.append(child)

    if len(wpts) >= 2:
        score += 10
        feedback_parts.append(f"Waypoints preserved ({len(wpts)})")
    else:
        feedback_parts.append(f"Insufficient waypoints (Found: {len(wpts)})")

    if len(trks) >= 1:
        score += 10
        feedback_parts.append("Track data preserved")
    else:
        feedback_parts.append("Track data missing (Did not export full collection)")

    # 4. Annotation Checks
    alpha_wpt = None
    beta_wpt = None
    coords_ok = True
    
    for wpt in wpts:
        lat = float(wpt.attrib.get('lat', 0))
        lon = float(wpt.attrib.get('lon', 0))
        
        if bounds:
            if not (bounds['min_lat'] <= lat <= bounds['max_lat'] and 
                    bounds['min_lon'] <= lon <= bounds['max_lon']):
                coords_ok = False
                
        # Aggregate text from desc/cmt fields
        text_content = ""
        for sub in wpt.iter():
            sub_tag = strip_namespace(sub.tag)
            if sub_tag in ['cmt', 'desc'] and sub.text:
                text_content += sub.text + " "
                
        if alpha_1 in text_content and alpha_2 in text_content:
            alpha_wpt = wpt
        if beta_1 in text_content and beta_2 in text_content:
            beta_wpt = wpt

    if alpha_wpt is not None:
        score += 20
        feedback_parts.append("Alpha annotation found")
    else:
        feedback_parts.append("Alpha annotation missing/incorrect")

    if beta_wpt is not None:
        score += 20
        feedback_parts.append("Beta annotation found")
    else:
        feedback_parts.append("Beta annotation missing/incorrect")

    if alpha_wpt is not None and beta_wpt is not None and alpha_wpt != beta_wpt:
        score += 5
        feedback_parts.append("Annotations correctly mapped to distinct waypoints")
    elif alpha_wpt is not None and alpha_wpt == beta_wpt:
        feedback_parts.append("FAIL: Both annotations crammed into single waypoint")

    if coords_ok:
        score += 10
        feedback_parts.append("Original coordinates preserved")
    else:
        feedback_parts.append("WARNING: Waypoint coordinates modified/out of bounds")

    # 5. Anti-gaming Checks
    if result.get('file_created_during_task'):
        score += 5
        feedback_parts.append("File generated during task session")
    else:
        feedback_parts.append("WARNING: File timestamps predate task (Pre-staged file?)")

    # 6. VLM Trajectory Verification
    vlm_results = query_trajectory_vlm(traj)
    if vlm_results.get("properties_dialog_used") and vlm_results.get("export_dialog_used"):
        score += 10
        feedback_parts.append("VLM confirmed expected workflow UI usage")

    os.unlink(gpx_file.name)

    # Passing conditions (Requires ≥60 and at least one annotation found correctly)
    passed = score >= 60 and (alpha_wpt is not None or beta_wpt is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }