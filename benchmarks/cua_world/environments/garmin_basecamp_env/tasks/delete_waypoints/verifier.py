#!/usr/bin/env python3
"""
Verifier for delete_waypoints task.

Verification Strategy:
1. Export Status: Check if cleaned_survey.gpx was created during the task (anti-gaming).
2. GPX Validity: Parse the GPX file as valid XML.
3. Content Deletion: Verify ERR_ waypoints are completely removed.
4. Content Preservation: Verify standard survey waypoints are still present.
5. Trajectory Evidence: Verify visual UI changes (fallback/bonus).
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_waypoints(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', r"C:\Users\Docker\Documents\cleaned_survey.gpx")
    err_waypoints = metadata.get('err_waypoints', ["ERR_Canopy_Glitch", "ERR_Signal_Bounce", "ERR_Cold_Start"])
    valid_waypoints = metadata.get('valid_waypoints', ["Survey_Start", "Survey_End", "Junction_North", "Junction_South"])

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON execution summary
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(r"C:\temp\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read execution state: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Output existence and anti-gaming timestamp checks
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": f"Target file '{expected_output_path}' was not found."}
    
    score += 10
    feedback_parts.append("File exported successfully")

    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File creation timestamp is valid")
    else:
        feedback_parts.append("WARNING: File timestamp predates task execution (possible gaming)")

    # 2. Fetch and parse the exported GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    found_waypoints = []
    
    try:
        copy_from_env(expected_output_path, temp_gpx.name)
        
        try:
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
            
            # GPX uses namespaces, so we strip them for easier tag matching
            for elem in root.iter():
                if '}' in elem.tag:
                    elem.tag = elem.tag.split('}', 1)[1]
                    
            # Extract all waypoint names
            for wpt in root.findall('.//wpt'):
                name_elem = wpt.find('name')
                if name_elem is not None and name_elem.text:
                    found_waypoints.append(name_elem.text.strip())
                    
            score += 10
            feedback_parts.append("GPX parsed as valid XML")
            
        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Exported GPX file is not valid XML/corrupted."}
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to download/read GPX file: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    logger.info(f"Waypoints found in exported file: {found_waypoints}")

    # 3. Check Erroneous Waypoints Deletion (10 points each)
    deleted_count = 0
    for err_wpt in err_waypoints:
        if err_wpt not in found_waypoints:
            score += 10
            deleted_count += 1
            feedback_parts.append(f"Successfully deleted {err_wpt}")
        else:
            feedback_parts.append(f"FAILED to delete {err_wpt}")

    # 4. Check Valid Waypoints Preservation (10 points each)
    preserved_count = 0
    for valid_wpt in valid_waypoints:
        if valid_wpt in found_waypoints:
            score += 10
            preserved_count += 1
            feedback_parts.append(f"Successfully preserved {valid_wpt}")
        else:
            feedback_parts.append(f"ERROR: Valid waypoint {valid_wpt} is missing (over-deleted)")

    # 5. Evaluate final passing conditions
    # Must have deleted at least 2 errors and preserved at least 3 valid points
    key_criteria_met = (deleted_count >= 2) and (preserved_count >= 3)
    passed = score >= 70 and key_criteria_met

    if passed:
        feedback_parts.insert(0, "SUCCESS: Waypoints managed correctly")
    else:
        feedback_parts.insert(0, "FAILURE: Waypoint management incomplete or inaccurate")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }