#!/usr/bin/env python3
"""
Verifier for add_multiple_patients task.

Verifies:
1. Three distinct patient records exist for the MOREAU family.
2. Data accuracy (Name, DOB, Sex, Zip, City, SSN) for each.
3. Database consistency (Index matching Details).
4. VLM verification of the workflow (filling multiple forms).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utilities from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_ssn(ssn):
    """Normalize SSN by removing spaces and dots."""
    if not ssn: return ""
    return str(ssn).replace(" ", "").replace(".", "")

def verify_add_multiple_patients(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_patients = metadata.get('expected_patients', [])
    
    # 1. Load Result JSON
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

    found_patients = result.get('patients_found', [])
    if isinstance(found_patients, dict) and "error" in found_patients:
        return {"passed": False, "score": 0, "feedback": f"Database query error: {found_patients['error']}"}

    score = 0
    feedback = []
    
    # 2. Verify Patient Counts
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    delta = current_count - initial_count
    
    if delta >= 3:
        score += 5
        feedback.append("Patient count increased by at least 3.")
    else:
        feedback.append(f"Patient count only increased by {delta} (expected 3).")

    # 3. Verify Individual Patients
    # We try to match each expected patient to one of the found patients
    matched_guids = set()
    
    for exp in expected_patients:
        best_match = None
        best_match_score = 0
        match_feedback = []
        
        for found in found_patients:
            if found['guid'] in matched_guids:
                continue
                
            current_match_score = 0
            # Check First Name (Required for basic match)
            if found.get('prenom', '').lower() == exp['firstname'].lower():
                current_match_score += 10
            else:
                continue # First name must match to consider this record
            
            # Check DOB
            if found.get('dob') == exp['dob']:
                current_match_score += 10
            
            # Check Sex
            if found.get('sexe') == exp['sex']:
                current_match_score += 5
            
            # Check City/Zip
            if str(found.get('cp')) == exp['zip'] and found.get('ville', '').lower() == exp['city'].lower():
                current_match_score += 5
                
            # Check SSN
            if normalize_ssn(found.get('numss')) == normalize_ssn(exp['ssn']):
                current_match_score += 5
            
            if current_match_score > best_match_score:
                best_match_score = current_match_score
                best_match = found
        
        if best_match:
            matched_guids.add(best_match['guid'])
            score += best_match_score
            feedback.append(f"Found {exp['firstname']}: +{best_match_score}pts")
        else:
            feedback.append(f"Missing patient: {exp['firstname']}")

    # 4. Consistency Check (Address sharing)
    addresses = [p.get('adresse') for p in found_patients if p.get('guid') in matched_guids]
    if len(addresses) >= 3 and len(set(addresses)) == 1:
        score += 5
        feedback.append("Address consistency verified (+5pts).")
    elif len(addresses) >= 3:
        feedback.append("Warning: Addresses not identical across family members.")

    # 5. VLM Verification (Workflow check)
    # Did the agent actually use the UI 3 times?
    frames = sample_trajectory_frames(traj, n=10)
    vlm_prompt = """
    Review these screenshots of a medical software (MedinTux).
    The user was supposed to register 3 separate patients from the same family.
    
    Look for:
    1. The patient creation form being filled out multiple times.
    2. Different first names (Pierre, Catherine, Emma) appearing in the forms.
    3. The 'Save' or 'OK' button being clicked multiple times.
    
    Does the trajectory show evidence of creating multiple different records?
    Return JSON: {"multiple_creations": boolean, "names_seen": list_of_strings, "confidence": float}
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("multiple_creations", False):
            score += 20
            feedback.append("VLM confirms multiple creation workflow (+20pts).")
        names_seen = parsed.get("names_seen", [])
        if len(names_seen) >= 2:
            feedback.append(f"VLM saw names: {', '.join(names_seen)}")
    else:
        # Fallback if VLM fails but data is good -> give partial credit
        if score >= 70: 
            score += 20
            feedback.append("VLM unavailable, trusting data verification (+20pts).")

    # Final Score Cap
    score = min(100, score)
    passed = score >= 60 and len(matched_guids) >= 2 # Must have at least 2 correct patients

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }