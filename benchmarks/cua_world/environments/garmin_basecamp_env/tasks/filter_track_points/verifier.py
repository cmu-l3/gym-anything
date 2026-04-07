#!/usr/bin/env python3
"""
Verifier for filter_track_points task in Garmin BaseCamp.

Uses multiple independent signals (File logic, GPX Data Geometry, Timestamp, VLM)
to ensure task is completed realistically and robustly.
"""

import json
import os
import tempfile
import logging
import re
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_filter_track_points(traj, env_info, task_info):
    """
    Evaluates the simplified GPX track ensuring formatting, size, and geometry match expectations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_track_name', 'Fells_Loop_500')
    max_points = metadata.get('target_max_points', 500)
    min_points = metadata.get('min_points', 100)

    # 1. Access Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Accommodate dockur/Windows paths appropriately
        try:
            copy_from_env("C:/tmp/task_result.json", temp_result.name)
        except:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            
        with open(temp_result.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    # 2. File State Evaluation (25 pts)
    output_exists = result.get('output_exists', False)
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output GPX file not found."}

    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was created before task start")

    file_content = result.get('file_content', '')
    if not file_content:
        return {"passed": False, "score": score, "feedback": "GPX file is empty."}

    # 3. XML Geometry Parsing
    xml_string = re.sub(r'\sxmlns="[^"]+"', '', file_content, count=1)  # strip namespace 
    try:
        root = ET.fromstring(xml_string)
        score += 10
        feedback_parts.append("Valid GPX XML")
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Invalid XML format: {e}"}

    def find_all(el, tag):
        return [e for e in el.iter() if e.tag.endswith(tag)]

    trks = find_all(root, 'trk')
    if not trks:
        return {"passed": False, "score": score, "feedback": "No <trk> element found."}

    # 4. Content Verification: Track Name (15 pts)
    name_elements = find_all(trks[0], 'name')
    track_name = name_elements[0].text if name_elements and name_elements[0].text else ""
    
    if track_name == expected_name:
        score += 15
        feedback_parts.append(f"Track appropriately named '{expected_name}'")
    elif track_name.lower() == expected_name.lower():
        score += 10
        feedback_parts.append(f"Track named with wrong case: '{track_name}'")
    else:
        feedback_parts.append(f"Track name mismatch: got '{track_name}'")

    # 5. Content Verification: Filter Point Limits (20 pts)
    trkpts = find_all(trks[0], 'trkpt')
    point_count = len(trkpts)
    
    if min_points <= point_count <= max_points:
        score += 20
        feedback_parts.append(f"Point count valid ({point_count})")
    else:
        feedback_parts.append(f"Point count invalid: {point_count} (expected {min_points}-{max_points})")

    # 6. Anti-Gaming Check: Geographic Bounds (20 pts)
    lats = [float(pt.attrib.get('lat', 0)) for pt in trkpts if 'lat' in pt.attrib]
    lons = [float(pt.attrib.get('lon', 0)) for pt in trkpts if 'lon' in pt.attrib]

    if lats and lons:
        # Middlesex fells baseline box checks
        if 42.40 <= min(lats) <= 42.50 and 42.40 <= max(lats) <= 42.50 and \
           -71.20 <= min(lons) <= -71.00 and -71.20 <= max(lons) <= -71.00:
            score += 20
            feedback_parts.append("Bounds correctly match real Fells data")
        else:
            feedback_parts.append("Geographic bounds incorrect (Not actual survey data)")
    else:
        feedback_parts.append("No valid coordinates")

    # 7. Supplemental Verification: VLM Trajectory Process Check (20 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if frames and final:
            prompt = """
            You are verifying a Garmin BaseCamp GIS task. Examine the provided frames.
            Did the agent open the 'Filter Track' dialog and configure a 'Maximum Points' value (e.g. 500)?
            Respond in JSON format: {"filter_dialog_used": true/false}
            """
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res:
                parsed = vlm_res.get("parsed") if isinstance(vlm_res, dict) else None
                if parsed and parsed.get("filter_dialog_used", False):
                    score += 20
                    feedback_parts.append("VLM visual confirmed filter dialog usage")
                elif isinstance(vlm_res, dict) and "true" in vlm_res.get("response", "").lower():
                    score += 20
                    feedback_parts.append("VLM text confirmed filter dialog usage")
                else:
                    feedback_parts.append("VLM: Dialog usage not visually confirmed")
    except ImportError:
        feedback_parts.append("VLM skipped (import error)")
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        feedback_parts.append(f"VLM error: {e}")

    # Minimum pass threshold ensures key data processing goals are met
    passed = score >= 85 and (min_points <= point_count <= max_points)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }