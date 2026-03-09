#!/usr/bin/env python3
"""
Verifier for assign_investigator_conditional task.

Logic:
1. Check Ground Truth Risk Level (0=Low, 1=High).
2. Check Participants in the Case via API dump.
3. Validate:
   - If High Risk: Nick Wilde MUST be present, Judy Hopps MUST NOT.
   - If Low Risk: Judy Hopps MUST be present, Nick Wilde MUST NOT.
4. VLM Verification: Confirm navigation to People module (Subject Lookup).
"""

import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_investigator_conditional(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    import tempfile
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_case = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        # Load the raw case data dumped from API
        case_dump_path = result_data.get("case_data_dump_path")
        copy_from_env(case_dump_path, temp_case.name)
        with open(temp_case.name, 'r') as f:
            case_data = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_case.name): os.unlink(temp_case.name)

    # 2. Extract Data
    risk_level = result_data.get("risk_level_ground_truth", 0) # 0=Low, 1=High
    participants = case_data.get("participants", [])
    
    # Normalize participant names for checking
    # Participant structure might be complex objects, extract names
    participant_names = []
    if isinstance(participants, list):
        for p in participants:
            # Handle various potential API structures (e.g. nested person object)
            p_str = json.dumps(p).lower()
            if "nick" in p_str and "wilde" in p_str:
                participant_names.append("nick_wilde")
            if "judy" in p_str and "hopps" in p_str:
                participant_names.append("judy_hopps")
    
    logger.info(f"Risk Level: {risk_level}, Participants Found: {participant_names}")

    # 3. Logic Verification
    score = 0
    feedback = []
    passed = False
    
    has_nick = "nick_wilde" in participant_names
    has_judy = "judy_hopps" in participant_names

    # Check for empty participants
    if not has_nick and not has_judy:
        feedback.append("No investigator was assigned.")
        return {"passed": False, "score": 0, "feedback": "Failed: No investigator assigned."}

    # Check logic
    if risk_level == 1: # High Risk
        feedback.append("Scenario was HIGH RISK.")
        if has_nick and not has_judy:
            score += 70
            feedback.append("Correctly assigned Nick Wilde (High Risk Protocol).")
            passed = True
        elif has_nick and has_judy:
            score += 30
            feedback.append("Assigned Nick Wilde, but incorrectly ALSO assigned Judy Hopps.")
            passed = False
        elif has_judy:
            score += 0
            feedback.append("INCORRECT: Assigned Judy Hopps to a High Risk subject. Safety violation.")
            passed = False
    else: # Low Risk
        feedback.append("Scenario was LOW RISK.")
        if has_judy and not has_nick:
            score += 70
            feedback.append("Correctly assigned Judy Hopps (Low Risk Protocol).")
            passed = True
        elif has_judy and has_nick:
            score += 30
            feedback.append("Assigned Judy Hopps, but incorrectly ALSO assigned Nick Wilde.")
            passed = False
        elif has_nick:
            score += 0
            feedback.append("INCORRECT: Assigned Nick Wilde to a Low Risk subject. Resource misallocation.")
            passed = False

    # 4. VLM Verification (Did they look up the person?)
    # We want to see if the agent visited the 'People' module or searched for 'Victor'
    frames = sample_trajectory_frames(traj, n=8)
    vlm_prompt = """
    Review these screenshots of an agent performing a task.
    The agent was supposed to:
    1. Look at a Complaint case.
    2. Go to the 'People' module (or Search) to look up 'Victor Vance'.
    3. Read his profile notes.
    4. Return to the case.
    
    Do you see evidence that the agent visited a User Profile or People Search screen for 'Victor'?
    Look for:
    - A screen titled 'People' or 'Person Details'
    - The name 'Victor' or 'Vance'
    - Text like 'History of violence' or 'No prior record'
    
    Answer YES or NO and provide a confidence score (0-10).
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_text = vlm_res.get("result", "").lower()
        
        if "yes" in vlm_text:
            score += 30
            feedback.append("VLM confirms agent checked the subject's profile.")
        else:
            feedback.append("VLM did not clearly see the agent checking the subject's profile.")
            # We don't fail them if they got the right answer (maybe they guessed or used a method invisible to VLM), 
            # but they lose points.
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback.append("VLM verification skipped due to error.")

    return {
        "passed": passed and score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }