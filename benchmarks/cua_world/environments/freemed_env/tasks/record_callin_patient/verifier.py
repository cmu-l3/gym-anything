#!/usr/bin/env python3
"""
Verifier for record_callin_patient task.

Checks database outputs (callin and patient tables) for accurate transcription 
of the caller's details. Includes VLM trajectory checks to ensure the workflow
matched the administrative scenario.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these screenshots of a medical application workflow.
    
Task check:
1. Did the user navigate to the "Call-In Patient" or "Call-In" module? (Look at titles/menus).
2. Did the user enter information for "Margaret Whitfield"?

Provide a JSON response ONLY:
{
    "used_callin_module": true/false,
    "entered_margaret_data": true/false,
    "observations": "brief summary of the workflow seen"
}"""


def verify_record_callin_patient(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely retrieve exported result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    callin_dump = result.get('callin_dump', '').lower()
    patient_dump = result.get('patient_dump', '').lower()
    
    init_callin = result.get('initial_callin_count', 0)
    final_callin = result.get('final_callin_count', 0)
    
    init_patient = result.get('initial_patient_count', 0)
    final_patient = result.get('final_patient_count', 0)
    
    # 1. Anti-gaming: Ensure they actually created a new row
    if final_callin > init_callin:
        score += 15
        feedback.append("Call-In record count increased (+15)")
    else:
        feedback.append("No new Call-In records detected")

    # 2. Check Name Details
    if 'margaret' in callin_dump and 'whitfield' in callin_dump:
        score += 20
        feedback.append("Name 'Margaret Whitfield' found in Call-In table (+20)")
    elif 'margaret' in callin_dump or 'whitfield' in callin_dump:
        score += 10
        feedback.append("Partial name found in Call-In table (+10)")
    else:
        feedback.append("Name not found in Call-In table")

    # 3. Check Complaint
    if 'back' in callin_dump and 'pain' in callin_dump:
        score += 15
        feedback.append("Complaint 'back pain' accurately recorded (+15)")
    elif 'back' in callin_dump or 'pain' in callin_dump:
        score += 5
        feedback.append("Partial complaint recorded (+5)")
    else:
        feedback.append("Complaint not found")

    # 4. Check Phone Numbers
    if '3847' in callin_dump and '9201' in callin_dump:
        score += 15
        feedback.append("Both phone numbers correctly recorded (+15)")
    elif '3847' in callin_dump or '9201' in callin_dump:
        score += 5
        feedback.append("One phone number recorded (+5)")
        
    # 5. Check DOB
    if '1978' in callin_dump or '07/22' in callin_dump or '22/07' in callin_dump:
        score += 10
        feedback.append("DOB accurately recorded (+10)")

    # 6. Correct Module Check (Anti-gaming/Penalty)
    # The task explicitly asks to use the Call-In module, NOT to register a full patient.
    if final_patient > init_patient and ('margaret' in patient_dump and 'whitfield' in patient_dump):
        # Heavy penalty if they used the standard New Patient module instead
        score = min(score, 40) 
        feedback.append("PENALTY: Added as a standard Patient instead of Call-In Patient. Max score capped at 40.")

    # 7. VLM Trajectory Verification (Optional/Supplementary)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_res = query_vlm(prompt=build_vlm_prompt(), images=images)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_callin_module') and parsed.get('entered_margaret_data'):
                        score += 25
                        feedback.append("VLM confirmed correct Call-In module usage (+25)")
                    else:
                        feedback.append("VLM did not confirm Call-In module usage.")
                else:
                    feedback.append("VLM query failed, skipped visual verification.")
        except ImportError:
            feedback.append("VLM frame sampling unavailable, skipped.")
    else:
        # If VLM is not available, scale the programmatic score to 100
        # Programmatic max without VLM is 75 points.
        score = int(score * (100.0 / 75.0))
        feedback.append("VLM unavailable - scaled programmatic score to 100.")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }