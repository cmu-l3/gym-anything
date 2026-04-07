#!/usr/bin/env python3
"""
Verifier for add_lab_test_dictionary task in FreeMED.

Uses a highly robust MULTI-SIGNAL VERIFICATION strategy:
1. DB Name Delta - ensures the exact string was newly committed (Anti-Gaming)
2. DB Code Delta - ensures the test code/abbreviation was added
3. Structural Integrity - ensures the string was actually saved to a systemic support table, not arbitrarily typed into a generic message/patient note.
4. VLM Trajectory (Optional/Supplementary) - examines frames for logical progression.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_lab_test_dictionary(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the result JSON evaluated during the post_task hook
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # =================================================================
    # CRITERION 1: DB Name Persisted & Delta (25 points)
    # =================================================================
    initial_name = result.get("initial_name_count", 0)
    final_name = result.get("final_name_count", 0)
    
    if final_name > initial_name:
        score += 25
        feedback_parts.append(f"Name persisted (count increased {initial_name}->{final_name})")
    else:
        feedback_parts.append("Test Name not found in new DB records")

    # =================================================================
    # CRITERION 2: DB Code Persisted & Delta (20 points)
    # =================================================================
    initial_code = result.get("initial_code_count", 0)
    final_code = result.get("final_code_count", 0)
    
    if final_code > initial_code:
        score += 20
        feedback_parts.append(f"Code persisted (count increased {initial_code}->{final_code})")
    else:
        feedback_parts.append("Test Code not found in new DB records")

    # =================================================================
    # CRITERION 3: Structural Integrity Check (25 points)
    # =================================================================
    found_in_table = result.get("found_in_table", "").lower()
    
    # Tables that indicate the user just typed the text into random, non-dictionary areas
    invalid_tables = ["patient", "user", "log", "message", "letter", "note", "encounter", "audit", "callin"]

    if not found_in_table:
        feedback_parts.append("Record not structurally found in any DB table")
    else:
        is_invalid = any(inv in found_in_table for inv in invalid_tables)
        if is_invalid:
            feedback_parts.append(f"FAIL: Record found in incorrect entity table ({found_in_table}) - not a dictionary")
        else:
            score += 25
            feedback_parts.append(f"Structural integrity passed (Table: {found_in_table})")

    # =================================================================
    # CRITERION 4: VLM Trajectory Check (30 points)
    # =================================================================
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)

            prompt = """Examine these sequential screenshots from a web-based Electronic Medical Record system (FreeMED).
Task: The user is supposed to add a new lab test to the system's master dictionary/support data.
Look through the trajectory of actions.
Did the user navigate to a configuration/administration/support data module and fill out a form for a new Lab Test or Order Type?
Respond with JSON strictly following this schema:
{"navigated_to_admin": true/false, "filled_lab_test_form": true/false}"""

            vlm_result = query_vlm(images=frames + [final], prompt=prompt)
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("navigated_to_admin") and parsed.get("filled_lab_test_form"):
                vlm_score = 30
                feedback_parts.append("VLM confirmed trajectory (Admin + Form)")
            elif parsed.get("navigated_to_admin") or parsed.get("filled_lab_test_form"):
                vlm_score = 15
                feedback_parts.append("VLM partially confirmed trajectory")
            else:
                feedback_parts.append("VLM did not confirm correct trajectory")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM verification failed")
    else:
        feedback_parts.append("VLM not available")

    score += vlm_score

    # To pass: Minimum 70 points ensures they successfully achieved DB persistency at the very least
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }