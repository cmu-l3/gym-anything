#!/usr/bin/env python3
"""
Verifier for import_csv_column_mapping task.
Evaluates if the agent correctly mapped and imported a generic CSV file.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a visual trajectory of a user interacting with Subsurface Dive Log.
Did the user interact with the "CSV Import" dialog? This dialog typically contains a data table preview of a CSV file where the user can click on column headers (dropdown menus) to map them to specific fields like "Date", "Location", "Max. Depth", etc.

Analyze the trajectory frames and respond in valid JSON format:
{
    "used_csv_import": true/false,
    "reasoning": "Briefly describe if and when the CSV Import mapping window was visible."
}"""

def verify_import_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read metadata from export
    result_meta = {}
    tmp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_meta.close()
    try:
        copy_from_env('/tmp/task_result.json', tmp_meta.name)
        with open(tmp_meta.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read task_result.json: {e}")
    finally:
        if os.path.exists(tmp_meta.name):
            os.unlink(tmp_meta.name)

    # 2. Check File Modification Anti-Gaming (10 points)
    file_modified = result_meta.get("file_modified", False)
    if file_modified:
        score += 10
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified (did you save?)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Read and Parse the Saved XML Logbook
    tmp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_ssrf.close()
    
    dives_parsed = []
    try:
        copy_from_env('/home/ga/Documents/dives.ssrf', tmp_ssrf.name)
        tree = ET.parse(tmp_ssrf.name)
        root = tree.getroot()
        dives_parsed = list(root.iter('dive'))
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse saved dive log: {e}"}
    finally:
        if os.path.exists(tmp_ssrf.name):
            os.unlink(tmp_ssrf.name)

    # 4. Check Dive Count (15 points)
    # The sample starts with 8 dives. We added 3. Total should be 11.
    dive_count = len(dives_parsed)
    if dive_count >= 11:
        score += 15
        feedback_parts.append(f"Dive count={dive_count} (Expected ~11)")
    else:
        feedback_parts.append(f"Dive count={dive_count} (Import failed or not saved)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 5. Extract specific dives and verify mapping correctness
    # Target dates from the CSV: 2023-05-10, 2023-05-11, 2023-05-12
    # We will serialize the dive nodes to strings to easily check for deeply nested mapped values 
    # (handles differences in Subsurface internal XML schema versions effortlessly)
    
    dive_1 = next((d for d in dives_parsed if d.get('date') == '2023-05-10'), None)
    dive_2 = next((d for d in dives_parsed if d.get('date') == '2023-05-11'), None)
    dive_3 = next((d for d in dives_parsed if d.get('date') == '2023-05-12'), None)

    dates_found = sum(1 for d in [dive_1, dive_2, dive_3] if d is not None)
    if dates_found == 3:
        score += 15
        feedback_parts.append("All dates imported")
    elif dates_found > 0:
        score += 5 * dates_found
        feedback_parts.append(f"{dates_found}/3 dates imported")
    else:
        feedback_parts.append("Imported dates not found (Mapping failed?)")

    # Evaluate mapping completeness dynamically
    mapping_points = 0
    
    if dive_1 is not None:
        d_str = ET.tostring(dive_1).decode('utf-8').lower()
        if 'blue hole' in d_str: mapping_points += 5      # Location
        if '35' in d_str and '5' in d_str: mapping_points += 5 # Depth 35.5
        if 'manta ray' in d_str: mapping_points += 3      # Notes

    if dive_2 is not None:
        d_str = ET.tostring(dive_2).decode('utf-8').lower()
        if 'coral garden' in d_str: mapping_points += 5   # Location
        if '60' in d_str: mapping_points += 5             # Duration
        if 'nudibranchs' in d_str: mapping_points += 3    # Notes

    if dive_3 is not None:
        d_str = ET.tostring(dive_3).decode('utf-8').lower()
        if 'shark point' in d_str: mapping_points += 5    # Location
        if '28' in d_str: mapping_points += 5             # Depth
        if 'strong current' in d_str: mapping_points += 4 # Notes

    score += mapping_points
    if mapping_points >= 35:
        feedback_parts.append("Mappings look excellent")
    elif mapping_points >= 15:
        feedback_parts.append("Mappings partially correct")
    else:
        feedback_parts.append("Mappings missing or incorrect")

    # 6. VLM Check for Trajectory Interaction (20 points)
    # Ensure they didn't just type the 3 dives manually but actually used the CSV Import wizard
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=8)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_csv_import', False):
                    score += 20
                    feedback_parts.append("VLM confirmed CSV wizard use")
                else:
                    feedback_parts.append("VLM did NOT see CSV wizard")
            else:
                logger.warning("VLM query failed or returned no success.")
    except Exception as e:
        logger.warning(f"VLM verification step skipped or failed: {e}")
        # Give partial credit if VLM fails but file parsing was highly successful
        if mapping_points > 30:
            score += 20

    # Pass condition: File saved + dives added + significant portion of mapping was correct
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }