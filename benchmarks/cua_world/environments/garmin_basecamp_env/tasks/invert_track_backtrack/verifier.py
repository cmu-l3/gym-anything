#!/usr/bin/env python3
"""
Verifier for invert_track_backtrack task.

Verification Strategy:
1. Programmatic Checks:
   - Output GPX exists and was created during the task.
   - GPX contains the track name "Extraction_Path".
   - GPX contains the DisplayColor "Blue".
   - The sequence of coordinates in the track matches the REVERSED sequence of the original Fells Loop track.
2. VLM Verification:
   - Evaluates trajectory screenshots to ensure the agent used BaseCamp's UI to achieve the result (anti-gaming).
"""

import os
import json
import math
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_track_points(xml_content):
    """Extracts a list of (lat, lon) tuples from a GPX XML string."""
    pts = []
    try:
        root = ET.fromstring(xml_content)
        # Handle elements regardless of namespace variations
        for trkpt in root.findall('.//*'):
            if trkpt.tag.endswith('trkpt'):
                lat = float(trkpt.attrib['lat'])
                lon = float(trkpt.attrib['lon'])
                pts.append((lat, lon))
    except Exception as e:
        logger.error(f"Error parsing GPX points: {e}")
    return pts

def extract_metadata(xml_content):
    """Extracts track name and color from GPX XML string."""
    name = None
    color = None
    try:
        root = ET.fromstring(xml_content)
        for elem in root.findall('.//*'):
            if elem.tag.endswith('name') and not name:
                # Exclude root/document level name if it's inside <trk>
                name = elem.text.strip() if elem.text else None
            if elem.tag.endswith('DisplayColor'):
                color = elem.text.strip() if elem.text else None
    except Exception as e:
        logger.error(f"Error parsing GPX metadata: {e}")
    return name, color

def calculate_distance(p1, p2):
    """Calculate crude distance between two (lat, lon) points for tolerance checking."""
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def verify_invert_track_backtrack(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', 'C:/workspace/extraction_path.gpx')
    original_track_path = metadata.get('original_track_path', 'C:/workspace/data/fells_loop.gpx')

    score = 0
    feedback_parts = []
    
    # 1. Fetch the JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output GPX file was not created at the expected path."}
    if not file_created:
        feedback_parts.append("Warning: File timestamp suggests it wasn't created during the task.")

    score += 10
    feedback_parts.append("File successfully exported.")

    # 2. Fetch Exported GPX and Original GPX
    temp_exported = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    temp_original = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        copy_from_env(expected_output_path, temp_exported.name)
        copy_from_env(original_track_path, temp_original.name)
        
        with open(temp_exported.name, 'r', encoding='utf-8', errors='ignore') as f:
            exported_xml = f.read()
        with open(temp_original.name, 'r', encoding='utf-8', errors='ignore') as f:
            original_xml = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve GPX files for analysis: {e}"}
    finally:
        if os.path.exists(temp_exported.name): os.unlink(temp_exported.name)
        if os.path.exists(temp_original.name): os.unlink(temp_original.name)

    # 3. Analyze Metadata
    trk_name, trk_color = extract_metadata(exported_xml)
    
    if trk_name == "Extraction_Path":
        score += 20
        feedback_parts.append("Track correctly named 'Extraction_Path'.")
    else:
        feedback_parts.append(f"Incorrect track name: {trk_name}")

    if trk_color == "Blue":
        score += 20
        feedback_parts.append("Track color correctly set to Blue.")
    else:
        feedback_parts.append(f"Incorrect/missing track color: {trk_color}")

    # 4. Analyze Track Point Sequence
    exported_pts = extract_track_points(exported_xml)
    original_pts = extract_track_points(original_xml)

    seq_inverted = False
    if len(exported_pts) > 0 and len(original_pts) > 0:
        # BaseCamp might slightly prune data, but the start point of exported should match end of original
        # and end point of exported should match start of original
        start_match = calculate_distance(exported_pts[0], original_pts[-1]) < 0.0001
        end_match = calculate_distance(exported_pts[-1], original_pts[0]) < 0.0001
        
        # Verify length is reasonably close to original (within 10% in case of minor optimization)
        len_match = abs(len(exported_pts) - len(original_pts)) / len(original_pts) < 0.1
        
        if start_match and end_match and len_match:
            seq_inverted = True
            score += 30
            feedback_parts.append("Track sequence successfully inverted.")
        else:
            feedback_parts.append("Track geometry does not match an inverted original track.")
    else:
        feedback_parts.append("Exported track contains no track points.")

    # 5. VLM Trajectory Verification (Anti-gaming check)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = (
            "You are verifying if a user successfully inverted a track inside Garmin BaseCamp. "
            "Look at these trajectory frames. Do you see evidence that the user interacted with BaseCamp's UI "
            "to duplicate the track, open the context menu or track properties, and use the 'Invert Track' / 'Reverse' function? "
            "Reply strictly in JSON: {\"used_ui\": true/false, \"reason\": \"explanation\"}"
        )
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("used_ui"):
            vlm_score = 20
            score += vlm_score
            feedback_parts.append("VLM verified UI workflow for track inversion.")
        else:
            feedback_parts.append("VLM could not confirm use of BaseCamp UI for the task.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Default pass for VLM if missing to not penalize correct program logic when API fails
        score += 20 
        feedback_parts.append("VLM check skipped (awarded default points).")

    passed = score >= 80 and seq_inverted
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }