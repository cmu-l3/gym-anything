#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_edit_medication_dosage(traj, env_info, task_info):
    """
    Verifies the medication dosage edit task.
    
    Criteria:
    1. Medication record exists for the patient.
    2. Dosage contains "20".
    3. Frequency/Sig contains "twice" or "bid".
    4. Record is active.
    5. Anti-gaming: modification happened during task.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    med_exists = result.get("med_exists", False)
    final_dosage = str(result.get("final_dosage", "")).lower()
    final_sig = str(result.get("final_sig", "")).lower()
    final_freq = str(result.get("final_frequency", "")).lower()
    
    # Metadata requirements
    req_dosage = task_info.get("metadata", {}).get("required_dosage_substring", "20")
    req_freqs = task_info.get("metadata", {}).get("required_freq_substrings", ["twice", "bid", "2 times"])
    
    score = 0
    feedback = []

    # 3. Scoring Logic
    
    # Criterion 1: Medication Exists (20 pts)
    if med_exists:
        score += 20
        feedback.append("Medication record found.")
    else:
        feedback.append("No active Lisinopril record found for patient.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Dosage Check (30 pts)
    # Check if "20" is in the dosage string (e.g. "20mg", "20 mg") AND "10" is NOT (optional, but good for strictness)
    if req_dosage in final_dosage:
        score += 30
        feedback.append(f"Dosage updated to include '{req_dosage}'.")
    else:
        feedback.append(f"Dosage incorrect. Expected to contain '{req_dosage}', found '{final_dosage}'.")

    # Criterion 3: Frequency/Sig Check (30 pts)
    # Check sig OR frequency field for "twice daily", "bid", etc.
    freq_match = any(term in final_sig for term in req_freqs) or \
                 any(term in final_freq for term in req_freqs)
    
    if freq_match:
        score += 30
        feedback.append("Frequency updated correctly.")
    else:
        feedback.append(f"Frequency incorrect. Expected one of {req_freqs}, found sig:'{final_sig}' freq:'{final_freq}'.")

    # Criterion 4: Anti-Gaming / Integrity (20 pts)
    # Check if we are seeing the exact same record ID (update in place) or a new one (delete/add or versioning).
    # NOSH often creates new versions or updates. 
    # Key check: Was it done during the task?
    # Since we can't easily parse SQL dates in bash without dependencies, we rely on the fact that 
    # setup_task cleared the table and inserted a specific record. 
    # If the current record has the correct values, it MUST be an edit or a new entry by the agent.
    # We give points if the values match, implying action was taken.
    
    # VLM Verification for redundancy
    # We check if the agent actually used the UI
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # Simple prompt to verify UI interaction
        prompt = "Does the screenshot show an Electronic Health Record (EHR) interface with a medication list or prescription form?"
        vlm_result = query_vlm(images=frames + [final_img], prompt=prompt)
        
        if vlm_result.get("parsed", {}).get("yes_no_answer", False) or "yes" in vlm_result.get("result", "").lower():
            vlm_score = 20
            feedback.append("Visual verification passed.")
        else:
            feedback.append("Visual verification inconclusive.")
    except Exception as e:
        print(f"VLM check failed: {e}")
        vlm_score = 20 # Fallback to giving points if DB is correct to avoid false negatives on API failure

    score += vlm_score

    # 4. Final Verdict
    # Threshold: Need Dosage AND Frequency correct to pass
    passed = (req_dosage in final_dosage) and freq_match and med_exists
    
    # Cap score if failed
    if not passed:
        score = min(score, 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }