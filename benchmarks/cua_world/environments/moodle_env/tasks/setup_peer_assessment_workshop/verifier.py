#!/usr/bin/env python3
"""
Verifier for Setup Peer Assessment Workshop task in Moodle.

Criteria:
1. Workshop activity created with correct name (20 pts)
2. Instructions populated from text file (10 pts)
3. Grading strategy set to 'accumulative' (15 pts)
4. Assessment form defined with 3 aspects and exact max grades: 30, 40, 30 (25 pts)
5. Workshop phase switched to 'Submission phase' (Moodle internal phase ID 20) (15 pts)
6. VLM Trajectory Verification showing meaningful UI interaction (15 pts)

Total: 100 points. Pass threshold: 70 points.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify trajectory
VLM_PROMPT = """You are assessing a computer agent's trajectory while setting up a Moodle Workshop activity.
The user was instructed to create a 'Workshop', edit the 'Assessment form' to add a grading rubric, and switch the workshop phase to 'Submission'.

Look at these sampled screenshots from the agent's session and determine:
1. Did the agent navigate through Moodle's course editing interface?
2. Is there evidence of interacting with Workshop settings or the 'Edit assessment form' page?
3. Did the agent interact with the Workshop Planner UI (the table with lightbulbs used to switch phases)?

Respond in JSON format:
{
    "navigated_moodle": true/false,
    "edited_workshop_or_rubric": true/false,
    "interacted_with_phases": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_setup_peer_assessment_workshop(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy_from_env function missing."}

    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name_keywords = ["peer", "assessment", "end-of-life"]
    expected_strategy = metadata.get('expected_strategy', 'accumulative')
    expected_phase = metadata.get('expected_phase', 20)
    
    # 1. Retrieve the exported JSON from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    workshop_found = result.get('workshop_found', False)
    if not workshop_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Workshop activity was not found in the course. Task failed."
        }

    # CRITERION 1: Workshop Creation & Name (20 pts)
    workshop_name = result.get('workshop_name', '').lower()
    name_matches = sum(1 for kw in expected_name_keywords if kw in workshop_name)
    if name_matches == len(expected_name_keywords):
        score += 20
        feedback.append("Workshop created with correct name.")
    elif name_matches > 0:
        score += 10
        feedback.append(f"Workshop created, but name was partially incorrect: '{workshop_name}'.")
    else:
        feedback.append(f"Workshop created, but name was incorrect: '{workshop_name}'.")

    # CRITERION 2: Instructions Populated (10 pts)
    if result.get('instructions_set', False):
        score += 10
        feedback.append("Submission and Assessment instructions populated.")
    else:
        feedback.append("Instructions fields were missing or too short.")

    # CRITERION 3: Grading Strategy (15 pts)
    strategy = result.get('workshop_strategy', '')
    if strategy == expected_strategy:
        score += 15
        feedback.append(f"Grading strategy correctly set to {expected_strategy}.")
    else:
        feedback.append(f"Incorrect grading strategy: '{strategy}' (expected '{expected_strategy}').")

    # CRITERION 4: Aspects & Maximum Grades (25 pts)
    aspects = result.get('aspects', [])
    if strategy == expected_strategy and len(aspects) > 0:
        aspect_score = 0
        expected_grades = [30, 40, 30]
        found_grades = [a.get('grade', 0) for a in aspects]
        
        # Check if we have at least 3 aspects
        if len(found_grades) >= 3:
            aspect_score += 10
            feedback.append("At least 3 grading aspects defined.")
            
            # Check grades match exactly
            if sorted(found_grades[:3]) == sorted(expected_grades):
                aspect_score += 15
                feedback.append("Maximum grades match expected values (30, 40, 30).")
            else:
                aspect_score += 5
                feedback.append(f"Aspects created but max grades are incorrect: {found_grades}.")
        else:
            aspect_score += 5
            feedback.append(f"Only {len(found_grades)} aspects defined, expected 3.")
            
        score += aspect_score
    else:
        feedback.append("No grading aspects were defined (or wrong strategy).")

    # CRITERION 5: Workshop Phase Switched (15 pts)
    phase = result.get('workshop_phase', 0)
    if phase == expected_phase:
        score += 15
        feedback.append("Workshop successfully switched to Submission phase.")
    elif phase > expected_phase:
        score += 5
        feedback.append(f"Workshop phase bypassed Submission phase (current: {phase}).")
    else:
        feedback.append(f"Workshop still in Setup phase (current: {phase}).")

    # CRITERION 6: VLM Trajectory Verification (15 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("navigated_moodle") and parsed.get("edited_workshop_or_rubric"):
                    score += 15
                    feedback.append("VLM verified meaningful trajectory progression.")
                elif parsed.get("navigated_moodle"):
                    score += 5
                    feedback.append("VLM verified Moodle navigation, but lacked deeper workshop setup evidence.")
                else:
                    feedback.append("VLM could not confirm proper Moodle workflow in trajectory.")
            else:
                feedback.append("VLM query failed or returned no parsable output.")
        else:
            feedback.append("No trajectory frames available for VLM verification.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback.append("VLM verification skipped due to error.")

    passed = (score >= 70) and workshop_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "workshop_id": result.get("workshop_id"),
            "aspects_count": len(aspects),
            "phase": phase
        }
    }