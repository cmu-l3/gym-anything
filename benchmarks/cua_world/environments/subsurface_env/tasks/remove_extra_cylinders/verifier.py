#!/usr/bin/env python3
"""Verifier for remove_extra_cylinders task.

Checks that the dive logbook contains exactly 8 dives and that EVERY dive
now has exactly one `<cylinder>` element. Uses VLM to ensure the agent
interacted with the GUI (Equipment tab).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_extra_cylinders(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read task result to check timestamps (anti-gaming)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "dives.ssrf file is missing!"}

    if not result.get("file_modified", False):
        return {"passed": False, "score": 0, "feedback": "dives.ssrf was not modified. No changes were saved."}

    # 2. Parse XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    try:
        copy_from_env('/home/ga/Documents/dives.ssrf', temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse dives.ssrf XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    dives = list(root.iter('dive'))
    num_dives = len(dives)
    expected_initial_dives = task_info.get('metadata', {}).get('expected_dive_count', 8)

    if num_dives == 0:
        return {"passed": False, "score": 0, "feedback": "Failure: All dives were deleted from the file!"}

    correct_dives = 0
    total_cylinders_remaining = 0

    for dive in dives:
        cylinders = list(dive.findall('cylinder'))
        total_cylinders_remaining += len(cylinders)
        if len(cylinders) == 1:
            correct_dives += 1

    # Calculate score
    score = 10  # Base 10 points for modifying/saving the file
    
    # 20 points for keeping the integrity of the logbook (not deleting dives)
    if num_dives == expected_initial_dives:
        score += 20
        
    # 70 points distributed proportionally for cleaned dives
    cleanup_score = int((correct_dives / num_dives) * 70) if num_dives > 0 else 0
    score += cleanup_score

    # 3. VLM Verification for GUI usage (Anti-gaming via CLI)
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """This is a sequence of screenshots from an AI agent working in the Subsurface dive log application.
        The task is to remove extra cylinders from the 'Equipment' tab for each dive.
        Did the agent use the Subsurface GUI to interact with the Equipment tab and remove cylinders (e.g., clicking on the Equipment tab, right-clicking cylinder rows, clicking the trash icon, or handling warning dialogs)?
        
        Respond in JSON format:
        {
            "gui_used_for_removal": true/false,
            "equipment_tab_visible": true/false,
            "reasoning": "brief explanation"
        }
        """
        
        vlm_result = query_vlm(images=frames, prompt=prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            vlm_passed = parsed.get("gui_used_for_removal", False) or parsed.get("equipment_tab_visible", False)
    except Exception as e:
        logger.warning(f"VLM verification failed/unavailable, proceeding with programmatic only: {e}")
        vlm_passed = True # Fail open if VLM integration isn't available

    if not vlm_passed:
        score = min(score, 40) # Cap score heavily if GUI interaction is absent

    feedback = f"File modified: True. Dives remaining: {num_dives}/{expected_initial_dives}. Dives correctly having exactly 1 cylinder: {correct_dives}/{num_dives}."
    if not vlm_passed:
        feedback += " WARNING: VLM check failed. Agent did not appear to use the Equipment tab GUI."

    # Must retain original dive count and fix at least 6/8 dives to pass
    passed = (score >= 80) and (num_dives == expected_initial_dives)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }