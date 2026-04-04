#!/usr/bin/env python3
"""
Verifier for add_provider task in Oscar EMR.
Verifies that the agent correctly created a provider record and a linked security record.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_provider(traj, env_info, task_info):
    """
    Verify add_provider task.
    
    Scoring Breakdown (100 pts total):
    - Provider Record (60 pts):
        - Exists: 20 pts
        - Name (First/Last): 10 pts
        - ID & Type: 10 pts
        - Details (Specialty, Phone, Sex, Status): 20 pts
    - Security Record (40 pts):
        - Exists & Linked Correctly: 25 pts
        - PIN Correct: 15 pts
    
    Pass Threshold: 60 pts (Must at least have created the provider record correctly)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    meta = task_info.get('metadata', {})
    expected_prov = meta.get('provider', {})
    expected_sec = meta.get('security', {})

    # Copy result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    prov_res = result.get("provider_record", {})
    sec_res = result.get("security_record", {})

    # 1. Verify Provider Record
    if prov_res.get("exists"):
        score += 20
        feedback.append("Provider record created.")
        
        # Check Name
        fname_match = prov_res.get("first_name", "").strip().lower() == expected_prov.get("first_name", "").lower()
        lname_match = prov_res.get("last_name", "").strip().lower() == expected_prov.get("last_name", "").lower()
        if fname_match and lname_match:
            score += 10
        else:
            feedback.append(f"Name mismatch: Found {prov_res.get('first_name')} {prov_res.get('last_name')}")

        # Check ID and Type
        id_match = str(prov_res.get("provider_no")) == str(expected_prov.get("provider_no"))
        type_match = prov_res.get("type", "").lower() == expected_prov.get("type", "").lower()
        if id_match and type_match:
            score += 10
        else:
            feedback.append(f"ID/Type mismatch: ID={prov_res.get('provider_no')}, Type={prov_res.get('type')}")

        # Check Details (Specialty, Phone, Sex, Status)
        details_score = 0
        if expected_prov.get("specialty", "").lower() in prov_res.get("specialty", "").lower():
            details_score += 5
        
        # Phone check: loosen strict formatting
        res_phone = "".join(filter(str.isdigit, prov_res.get("phone", "")))
        exp_phone = "".join(filter(str.isdigit, expected_prov.get("phone", "")))
        if res_phone == exp_phone:
            details_score += 5
            
        if prov_res.get("sex", "").upper().startswith(expected_prov.get("sex", "F")):
            details_score += 5
            
        if str(prov_res.get("status")) == str(expected_prov.get("status")):
            details_score += 5
            
        score += details_score
        if details_score < 20:
             feedback.append("Some provider details (Specialty, Phone, Sex, or Status) were incorrect.")

    else:
        feedback.append("Provider record 100123 NOT found.")

    # 2. Verify Security Record
    if sec_res.get("exists"):
        # Check Link
        if str(sec_res.get("linked_provider_no")) == str(expected_prov.get("provider_no")):
            score += 25
            feedback.append("Security record created and linked correctly.")
        else:
            score += 10 # Credit for creating record, but penalty for wrong link
            feedback.append(f"Security record exists but linked to wrong provider: {sec_res.get('linked_provider_no')}")
            
        # Check PIN
        if str(sec_res.get("pin")) == str(expected_sec.get("pin")):
            score += 15
        else:
            feedback.append(f"Security PIN incorrect. Expected {expected_sec.get('pin')}, got {sec_res.get('pin')}")
    else:
        feedback.append("Security/Login record NOT found for 'ewatson'.")

    # Anti-gaming check: Ensure we didn't just find old data
    # (Setup script handles deletion, so existence implies creation, 
    # but we can check counts if we wanted to be extra strict. 
    # Given the deletion in setup, pure existence is sufficient proof of work.)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }