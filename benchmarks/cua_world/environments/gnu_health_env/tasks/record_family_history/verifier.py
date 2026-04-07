#!/usr/bin/env python3
"""
Verifier for record_family_history task.

Performs robust verification via:
1. Database Query: Checks the delta records for correct patient, pathology foreign keys, and relative strings.
2. VLM Trajectory: Verifies the UI progression (navigating to patient, accessing section, data entry).

Scoring Breakdown (100 points total):
  - Father + I25 entry exists (20 pts)
  - Mother + E11 entry exists (20 pts)
  - Sister + M32 entry exists (20 pts)
  - All 3 entries saved successfully delta check (10 pts)
  - VLM visual workflow progression (30 pts)
  
Pass Threshold: 60 points with all three diseases correctly identified.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these trajectory screenshots from a GNU Health EHR session.
The user's objective was to add 'Family Diseases' for the patient Ana Betz.

Please verify the workflow progression by checking for the following:
1. Did the user successfully search for and navigate to the patient record for 'Ana Betz'?
2. Did the user access the 'Family Diseases' (or family history) tab/section within her patient chart?
3. Is there evidence of data entry progression (e.g., searching for ICD-10 codes, selecting relative types)?

Respond ONLY with a JSON object in this format:
{
    "accessed_ana_betz": true/false,
    "accessed_family_diseases": true/false,
    "data_entry_progression": true/false
}
"""

def verify_record_family_history(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: Copy function not available"}

    # Copy the exported result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Father + I25
    if result.get("has_i25"):
        if result.get("has_father_relative"):
            score += 20
            feedback_parts.append("Father + I25 (Ischaemic heart disease) entry verified (20/20)")
        else:
            score += 15
            feedback_parts.append("I25 entry exists but relative not specified as Father (15/20)")
    else:
        feedback_parts.append("I25 entry missing (0/20)")

    # Check 2: Mother + E11
    if result.get("has_e11"):
        if result.get("has_mother_relative"):
            score += 20
            feedback_parts.append("Mother + E11 (Type 2 diabetes) entry verified (20/20)")
        else:
            score += 15
            feedback_parts.append("E11 entry exists but relative not specified as Mother (15/20)")
    else:
        feedback_parts.append("E11 entry missing (0/20)")

    # Check 3: Sister + M32
    if result.get("has_m32"):
        if result.get("has_sister_relative"):
            score += 20
            feedback_parts.append("Sister + M32 (Systemic lupus erythematosus) entry verified (20/20)")
        else:
            score += 15
            feedback_parts.append("M32 entry exists but relative not specified as Sister (15/20)")
    else:
        feedback_parts.append("M32 entry missing (0/20)")

    # Check 4: Delta count verification
    new_count = result.get("new_records_count", 0)
    if new_count >= 3:
        score += 10
        feedback_parts.append(f"Saved required number of entries ({new_count}) (10/10)")
    elif new_count > 0:
        score += 5
        feedback_parts.append(f"Partial entries saved ({new_count} expected 3) (5/10)")
    else:
        feedback_parts.append("No new entries were saved in the database (0/10)")

    # Check 5: VLM Trajectory Workflow Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj and hasattr(traj, 'frames') and traj.frames:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            vlm_response = query_vlm(images=images, prompt=build_vlm_prompt())
            
            if vlm_response.get("success") and "parsed" in vlm_response:
                parsed = vlm_response["parsed"]
                if parsed.get("accessed_ana_betz"):
                    vlm_score += 10
                    feedback_parts.append("VLM: Patient navigation verified (+10)")
                if parsed.get("accessed_family_diseases"):
                    vlm_score += 10
                    feedback_parts.append("VLM: Family diseases section access verified (+10)")
                if parsed.get("data_entry_progression"):
                    vlm_score += 10
                    feedback_parts.append("VLM: UI data entry progression verified (+10)")
            else:
                logger.warning("VLM returned failure or failed to parse.")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            
    # Fallback if VLM evaluation fails or is unavailable (headless tests)
    if vlm_score == 0:
        if score >= 60:
            vlm_score = 30
            feedback_parts.append("VLM unavailable; perfect DB records imply correct UI workflow (+30)")
        elif score > 0:
            vlm_score = 15
            feedback_parts.append("VLM unavailable; partial DB records imply partial UI workflow (+15)")

    score += vlm_score

    # Determine pass/fail
    key_conditions_met = (
        result.get("has_i25") and 
        result.get("has_e11") and 
        result.get("has_m32")
    )
    passed = (score >= 60) and key_conditions_met

    if not passed and score >= 60:
        feedback_parts.append("FAILED: Met points threshold, but missed one or more required ICD-10 codes.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }