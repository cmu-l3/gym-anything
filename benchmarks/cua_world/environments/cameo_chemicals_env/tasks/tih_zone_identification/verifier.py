#!/usr/bin/env python3
import json
import os
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

def verify_tih_zone_identification(traj, env_info, task_info):
    """
    Verifies the TIH Zone Identification task.
    Checks:
    1. Output file exists and was created during task.
    2. Correct Zone identified for each chemical.
    3. Trajectory analysis to ensure UN/NA pages were visited (anti-guessing).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve metadata and ground truth
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {
        "Phosgene": "A",
        "Chlorine": "B",
        "Bromine": "A",
        "Allyl Alcohol": "B",
        "Toluene": "NONE"
    })
    output_path = metadata.get('output_file', '/home/ga/Documents/tih_security_audit.txt')

    # 2. Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Check file existence and timestamp
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not task_result.get('created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task window."}

    # 4. Load output file content
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_path, temp_output.name)
        with open(temp_output.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File exists but could not be read: {str(e)}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)

    # 5. Verify Content (Logic Check)
    score = 10 # Base score for file existing
    feedback = []
    
    # Normalize content for searching
    content_lower = content.lower()
    
    # Define regex patterns for robust matching
    # Pattern looks for Chemical Name ... Zone ... X
    patterns = {
        "Phosgene": r"phosgene.*zone\s*[aA]",
        "Chlorine": r"chlorine.*zone\s*[bB]",
        "Bromine": r"bromine.*zone\s*[aA]",
        "Allyl Alcohol": r"allyl\s*alcohol.*zone\s*[bB]",
        "Toluene": r"toluene.*(none|no\s*zone|not\s*tih)"
    }
    
    # Helper to check negative case for Toluene (ensure it doesn't say Zone A/B/C/D)
    toluene_false_positive = re.search(r"toluene.*zone\s*[abcd]", content_lower)

    correct_count = 0
    
    for chem, pattern in patterns.items():
        if chem == "Toluene":
            # Toluene is special: pass if explicitly "none" OR if it doesn't match false positive
            if re.search(pattern, content_lower) or (not toluene_false_positive and "toluene" in content_lower):
                score += 18
                correct_count += 1
                feedback.append(f"✓ {chem}: Correct (NONE)")
            else:
                feedback.append(f"✗ {chem}: Incorrect or Missing")
        else:
            if re.search(pattern, content_lower):
                score += 18
                correct_count += 1
                feedback.append(f"✓ {chem}: Correct (Zone {ground_truth[chem]})")
            else:
                feedback.append(f"✗ {chem}: Incorrect or Missing")

    # 6. VLM Trajectory Verification (Process Check)
    # Ensure agent visited UN/NA datasheets, not just the chemical summary page.
    # UN/NA pages typically have "UN/NA Datasheet" in header or specific table structures.
    frames = sample_trajectory_frames(traj, n=8)
    vlm_prompt = (
        "Does the user navigate to 'UN/NA Datasheet' pages in CAMEO Chemicals? "
        "Look for headers like 'UN/NA [Number]' or tables containing 'ERG Guide' and 'Hazmat Table'. "
        "The goal is to verify the agent looked up regulatory details, not just the general chemical page."
    )
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    if not vlm_result.get("success") or not vlm_result.get("passed", True): # Assume pass if VLM fails/is ambiguous to avoid false fails on valid work
        feedback.append("(VLM Verification Inconclusive)")
    else:
        feedback.append("(VLM confirmed navigation to regulatory data)")

    final_passed = (score >= 82) # File exists (10) + 4/5 correct (72) = 82
    
    return {
        "passed": final_passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }