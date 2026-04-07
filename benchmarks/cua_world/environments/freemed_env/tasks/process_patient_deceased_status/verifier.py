#!/usr/bin/env python3
"""
Verifier for process_patient_deceased_status task.

Multi-Criteria Verification:
1. Patient record exists in database (10 points)
2. Date of Death (ptdod) correctly set to 2026-03-01 (60 points)
3. VLM Trajectory check confirms demographic editing workflow (30 points)

Anti-gaming: The setup script ensures ptdod is NULL before the task starts.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_patient_deceased_status(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dod = metadata.get('expected_dod', '2026-03-01')

    score = 0
    feedback_parts = []

    # Read the exported task result
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

    patient_found = result.get('patient_found', False)
    patient = result.get('patient', {})

    # Criterion 1: Patient Found (10 pts)
    if patient_found:
        score += 10
        feedback_parts.append("Patient 'Arthur Pendelton' found in database")

        # Criterion 2: Check Date of Death (60 pts)
        # We iterate over dictionary values to handle schema variations (e.g. ptdod vs ptdeathdate)
        dod_found = False
        for k, v in patient.items():
            if v and expected_dod in str(v):
                dod_found = True
                break

        if dod_found:
            score += 60
            feedback_parts.append(f"Date of Death correctly recorded as {expected_dod}")
        else:
            actual_dod = patient.get('ptdod', 'NULL')
            feedback_parts.append(f"Date of Death not found or incorrect (Expected: {expected_dod}, Found: {actual_dod})")
    else:
        feedback_parts.append("Patient 'Arthur Pendelton' NOT found in database")

    # Criterion 3: VLM Trajectory Verification (30 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            # Import framework VLM utilities dynamically
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final]

            prompt = (
                "Review these trajectory screenshots from a medical record system (FreeMED). "
                "Did the user actively edit the patient demographics for 'Arthur Pendelton', "
                "interact with the mortality/deceased status fields, and set a Date of Death? "
                "Respond strictly with a JSON object: {\"demographics_edited\": true/false}"
            )

            # Query the VLM
            vlm_res = query_vlm(prompt=prompt, images=images)
            
            # Check parsed VLM response
            parsed = vlm_res.get('parsed', {})
            if parsed.get('demographics_edited', False):
                score += 30
                feedback_parts.append("VLM confirmed demographic editing workflow")
            else:
                feedback_parts.append("VLM did not observe the demographic editing workflow")

        except ImportError:
            feedback_parts.append("VLM utilities not available for trajectory sampling")
        except Exception as e:
            feedback_parts.append(f"VLM verification error: {str(e)}")
    else:
        feedback_parts.append("VLM querying is not available")

    # Pass condition: Database correctly updated with expected date (meaning score >= 70)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }