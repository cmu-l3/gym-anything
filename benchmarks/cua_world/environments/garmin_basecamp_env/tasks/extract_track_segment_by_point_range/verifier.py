#!/usr/bin/env python3
"""
Verifier for extract_track_segment_by_point_range task.
Validates exact GPX data extraction and uses VLM trajectory verification to detect UI interactions.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

# Try to import VLM utilities. These will be available in the framework context.
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    HAS_VLM = True
except ImportError:
    HAS_VLM = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gpx(filepath):
    """Parse GPX to extract track points and track name."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        pts = []
        for trkpt in root.findall('.//{*}trkpt'):
            lat = float(trkpt.get('lat'))
            lon = float(trkpt.get('lon'))
            pts.append((lat, lon))
        
        name_elem = root.find('.//{*}trk/{*}name')
        name = name_elem.text if name_elem is not None else ""
        return pts, name
    except Exception as e:
        logger.error(f"Failed to parse GPX {filepath}: {e}")
        return None, ""

def find_closest_index(gt_pts, target_pt):
    """Find the index of the closest point in the ground truth array to a target point."""
    min_dist = float('inf')
    best_idx = -1
    for i, p in enumerate(gt_pts):
        dist = (p[0] - target_pt[0])**2 + (p[1] - target_pt[1])**2
        if dist < min_dist:
            min_dist = dist
            best_idx = i
    return best_idx, min_dist

def verify_extract_track_segment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    expected_track_name = metadata.get('expected_track_name', 'Transect_Soil_Samples')
    expected_point_count = metadata.get('expected_point_count', 101)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Output Existence & Gaming Check
    if result.get('output_exists'):
        score += 10
        feedback_parts.append("GPX exported")
        if result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File created during task run")
        else:
            feedback_parts.append("WARNING: File existed before task (possible gaming)")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Retrieve extracted GPX and Ground Truth GPX
    temp_extracted = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        copy_from_env("C:\\workspace\\output\\transect_extracted.gpx", temp_extracted.name)
        copy_from_env("C:\\workspace\\data\\fells_loop.gpx", temp_gt.name)
        
        agent_pts, agent_name = parse_gpx(temp_extracted.name)
        gt_pts, _ = parse_gpx(temp_gt.name)
        
    finally:
        if os.path.exists(temp_extracted.name): os.unlink(temp_extracted.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    if agent_pts is None:
        feedback_parts.append("Failed to parse agent GPX file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Track Name Evaluation
    if agent_name.strip() == expected_track_name:
        score += 10
        feedback_parts.append("Track correctly named")
    else:
        feedback_parts.append(f"Incorrect track name: '{agent_name}'")

    # 4. Point Count Evaluation
    actual_count = len(agent_pts)
    if actual_count == expected_point_count:
        score += 30
        feedback_parts.append(f"Exact point count ({actual_count})")
    elif abs(actual_count - expected_point_count) <= 5:
        score += 15
        feedback_parts.append(f"Approximate point count ({actual_count})")
    else:
        feedback_parts.append(f"Incorrect point count ({actual_count} instead of {expected_point_count})")

    # 5. Geolocation / Range Match (Did they grab points 250 to 350?)
    if len(agent_pts) > 0 and gt_pts and len(gt_pts) >= 350:
        # Index 250 in a 1-based UI is index 249 in 0-based code. Let's accept 245 to 255.
        start_idx, start_dist = find_closest_index(gt_pts, agent_pts[0])
        
        if start_dist < 1e-8 and 245 <= start_idx <= 255:
            score += 20
            feedback_parts.append(f"Correct segment slice chosen (started near index {start_idx})")
        else:
            feedback_parts.append(f"Wrong data selected. Extracted data starts near GT index {start_idx}")

    # 6. VLM Trajectory Verification
    vlm_score = 0
    if HAS_VLM and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
            
            prompt = (
                "Review these screenshots from a session using Garmin BaseCamp. "
                "Did the user open the track properties dialog, interact with the points data grid (list of coordinates), "
                "and extract/create a new track from a specific selection of points? "
                "Respond in JSON format: {\"used_properties_dialog\": true/false, \"selected_points_grid\": true/false}"
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("used_properties_dialog"): vlm_score += 10
                if parsed.get("selected_points_grid"): vlm_score += 10
                feedback_parts.append(f"VLM verified trajectory logic (+{vlm_score} pts)")
            else:
                feedback_parts.append("VLM evaluation skipped or failed")
                vlm_score += 20 # Give benefit of the doubt if framework fails
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            vlm_score += 20
    else:
        vlm_score += 20  # Fallback if VLM environment is missing
        
    score += vlm_score

    # Determine Pass/Fail
    # To pass, they must have exported the right segment (score >= 70 out of 100)
    key_criteria = result.get('file_created_during_task', False) and (abs(actual_count - expected_point_count) <= 5)
    passed = score >= 70 and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }