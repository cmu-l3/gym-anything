#!/usr/bin/env python3
"""
Verifier for close_track_loop_edit_point task.

Verification Strategy:
1. Copy metadata JSON and GPX file from the environment.
2. Programmatically verify GPX properties: existence, modification timestamp.
3. Parse GPX XML to strictly verify the mathematical closure of the loop.
4. Check metadata properties: renamed track, changed display color.
5. VLM trajectory verification: confirms agent used the UI properties dialog
   to extract/edit points rather than simply injecting a file via shell.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def strip_namespaces(node):
    """Recursively strip namespaces from XML tags for robust searching."""
    for elem in node.iter():
        if '}' in elem.tag:
            elem.tag = elem.tag.split('}', 1)[1]
    return node

def verify_close_track_loop(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', 'C:\\workspace\\output\\closed_boundary.gpx')
    expected_name = metadata.get('expected_track_name', 'Closed_Boundary_Loop')
    expected_color = metadata.get('expected_color', 'Yellow')
    min_points = metadata.get('min_points_threshold', 20)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp Check
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "GPX output file was not found."}
    
    if result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("File created/modified during task (+20)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file exists but was NOT modified during the task. No action detected."}

    # 3. Retrieve and Parse GPX File
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env(expected_output_path, temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = strip_namespaces(tree.getroot())
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse GPX XML: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    tracks = list(root.findall('.//trk'))
    if not tracks:
        return {"passed": False, "score": score, "feedback": "No tracks found in the exported GPX."}
    
    trk = tracks[0]
    
    # Check Name
    name_elem = trk.find('name')
    track_name = name_elem.text.strip() if name_elem is not None and name_elem.text else ""
    if track_name == expected_name:
        score += 10
        feedback_parts.append("Track renamed correctly (+10)")
    else:
        feedback_parts.append(f"Track name '{track_name}' != '{expected_name}'")

    # Check Color
    color_elem = trk.find('.//DisplayColor')
    track_color = color_elem.text.strip() if color_elem is not None and color_elem.text else ""
    if track_color == expected_color:
        score += 10
        feedback_parts.append("Track color updated (+10)")
    else:
        feedback_parts.append(f"Track color '{track_color}' != '{expected_color}'")

    # Check Track Points & Closure
    trkpts = list(trk.findall('.//trkpt'))
    num_pts = len(trkpts)
    loop_closed = False

    if num_pts >= min_points:
        score += 10
        feedback_parts.append("Point count preserved (+10)")
        
        first_pt, last_pt = trkpts[0], trkpts[-1]
        lat1, lon1 = float(first_pt.get('lat', 0)), float(first_pt.get('lon', 0))
        lat2, lon2 = float(last_pt.get('lat', 1)), float(last_pt.get('lon', 1))
        
        # Exact floating point match or within standard GPS tolerance (1e-6)
        if abs(lat1 - lat2) < 1e-6 and abs(lon1 - lon2) < 1e-6:
            loop_closed = True
            score += 30
            feedback_parts.append("Mathematical loop closure verified (+30)")
        else:
            feedback_parts.append(f"Loop NOT closed. Start ({lat1}, {lon1}) != End ({lat2}, {lon2})")
    else:
        feedback_parts.append(f"Track has too few points ({num_pts}). Data corrupted or faked.")

    # 4. VLM Trajectory Verification (Process Check)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = (
                "Task: Edit a track in Garmin BaseCamp.\n"
                "Review these trajectory screenshots from the agent's workflow.\n"
                "1. Did the agent open the track properties dialog in BaseCamp?\n"
                "2. Did the agent interact with the track point list view (editing a coordinate row)?\n"
                "Return JSON with boolean keys: 'opened_properties_dialog', 'interacted_with_point_list'."
            )
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("opened_properties_dialog"): vlm_score += 10
                if parsed.get("interacted_with_point_list"): vlm_score += 10
                
            score += vlm_score
            feedback_parts.append(f"VLM trajectory process verified (+{vlm_score})")
    except Exception as e:
        logger.warning(f"VLM trajectory check failed or unavailable: {e}")

    # Final logic evaluation
    key_criteria_met = loop_closed and result.get("file_created_during_task")
    passed = key_criteria_met and score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }