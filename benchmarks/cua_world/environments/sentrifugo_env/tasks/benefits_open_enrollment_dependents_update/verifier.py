#!/usr/bin/env python3
"""
Verifier for benefits_open_enrollment_dependents_update task.

Criteria:
1. EMP002 has dependent 'John Mitchell' (1985-04-12) [+20 pts]
2. EMP007 has dependent 'Emma Taylor' (2020-08-30) [+20 pts]
3. EMP007 has dependent 'Noah Taylor' (2022-11-15) [+20 pts]
4. EMP019 has dependent 'Alex Rivera' (1990-02-28) [+20 pts]
5. VLM trajectory verification: confirms agent used Sentrifugo Dependents UI [+20 pts]
6. Negative Constraint: EMP001 dog 'Buster Anderson' must NOT exist [-20 pts if violated]

Pass threshold: 60 points with the negative constraint successfully avoided.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dependents_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    dependents = result.get('dependents', [])
    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_dependents', [])
    negative = metadata.get('negative_constraint', {})
    
    # Helper to find a dependent in the DB export
    def find_dependent(empid, name_substring, dob_substring):
        for d in dependents:
            # Need to search keys defensively as schema column names might vary slightly
            record_empid = str(d.get('employeeId', '')).upper()
            
            # Find name field
            record_name = ""
            for k, v in d.items():
                if 'name' in k.lower() and isinstance(v, str):
                    record_name = v.lower()
                    break
                    
            # Find dob field
            record_dob = ""
            for k, v in d.items():
                if 'dob' in k.lower() or 'birth' in k.lower():
                    record_dob = str(v)
                    break

            if record_empid == empid and name_substring.lower() in record_name and record_dob.startswith(dob_substring):
                return True
        return False

    # Check 1: Sarah Mitchell's Spouse
    if find_dependent("EMP002", "john", "1985-04-12"):
        score += 20
        feedback_parts.append("John Mitchell (EMP002) added successfully.")
    else:
        feedback_parts.append("John Mitchell (EMP002) missing or incorrect.")

    # Check 2: Robert Taylor's Child 1
    if find_dependent("EMP007", "emma", "2020-08-30"):
        score += 20
        feedback_parts.append("Emma Taylor (EMP007) added successfully.")
    else:
        feedback_parts.append("Emma Taylor (EMP007) missing or incorrect.")

    # Check 3: Robert Taylor's Child 2
    if find_dependent("EMP007", "noah", "2022-11-15"):
        score += 20
        feedback_parts.append("Noah Taylor (EMP007) added successfully.")
    else:
        feedback_parts.append("Noah Taylor (EMP007) missing or incorrect.")

    # Check 4: Tyler Moore's Partner
    if find_dependent("EMP019", "alex", "1990-02-28"):
        score += 20
        feedback_parts.append("Alex Rivera (EMP019) added successfully.")
    else:
        feedback_parts.append("Alex Rivera (EMP019) missing or incorrect.")

    # Check Negative Constraint: James Anderson's Dog
    dog_found = False
    for d in dependents:
        record_empid = str(d.get('employeeId', '')).upper()
        record_name = str(d).lower()
        if record_empid == "EMP001" and "buster" in record_name:
            dog_found = True
            break
            
    if dog_found:
        score -= 20
        feedback_parts.append("FAILED NEGATIVE CONSTRAINT: Pet 'Buster' was added despite HR note. (-20 pts)")
    else:
        feedback_parts.append("Negative constraint respected (Pet 'Buster' ignored).")

    # VLM Trajectory Verification
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = (
            "Review these screenshots from a session interacting with the Sentrifugo HRMS. "
            "Did the user navigate to an employee's profile and actively use the 'Dependents' tab/form? "
            "We need to verify they used the web UI to enter the data. "
            "Respond in JSON format with a single boolean key 'used_dependents_ui'."
        )
        
        vlm_result = query_vlm(images=images, prompt=prompt)
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("used_dependents_ui", False):
            score += 20
            vlm_passed = True
            feedback_parts.append("VLM confirmed Dependents UI usage.")
        else:
            feedback_parts.append("VLM could not confirm Dependents UI usage (no UI trajectory).")
    except Exception as e:
        logger.warning(f"VLM verification failed or unavailable: {e}")
        feedback_parts.append(f"VLM verification skipped/failed: {e}")

    # Determine final success
    key_criteria_met = score >= 60
    passed = key_criteria_met and not dog_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }