#!/usr/bin/env python3
"""
Verifier for add_patient_insurance task.
Checks if the patient record for Lucas Silva has been updated with the correct insurance details
and that demographic data remains intact.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_patient_insurance(traj, env_info, task_info):
    """
    Verify the patient insurance update.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_provider = metadata.get('insurance_provider', "Cigna Health")
    expected_plan = metadata.get('insurance_plan', "PPO Standard")
    expected_policy = metadata.get('insurance_policy', "CIG-88421-99")
    expected_group = metadata.get('insurance_group', "G-4421")
    
    # Demographic data that MUST NOT change
    expected_name = metadata.get('expected_name', "Lucas Silva")
    expected_dob = metadata.get('expected_dob', "05/14/1982")

    # Load result from container
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

    # Basic checks
    if not result.get('doc_exists', False):
        return {"passed": False, "score": 0, "feedback": "Patient record P00008 not found in database."}

    patient_doc = result.get('patient_record', {})
    # HospitalRun data is often nested in a 'data' key, but sometimes flattened depending on API/version.
    # The seed data put it in 'data'.
    data = patient_doc.get('data', patient_doc)
    
    # 1. Anti-gaming check: Document modification
    initial_rev = result.get('initial_rev', "")
    current_rev = patient_doc.get('_rev', "")
    
    if initial_rev == current_rev:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The patient record was not modified (database revision matches initial state). You must save the changes."
        }

    score = 20 # Points for modifying the record
    feedback = ["Record modified successfully."]
    passed_criteria = []

    # 2. Extract Insurance Data
    # HospitalRun schema for insurance can vary, usually it's a list or specific fields.
    # We look for the insurance array or fields in the data object.
    insurance = data.get('insurance', [])
    
    # If insurance is an object (single entry), wrap it
    if isinstance(insurance, dict):
        insurance = [insurance]
        
    found_policy = None
    
    # Search through insurance entries for the target policy
    # Or check if fields exist directly on the patient object (legacy schema)
    
    # Helper to clean strings
    def clean(s): return str(s).strip().lower() if s else ""

    # Check list
    for ins in insurance:
        if clean(expected_policy) in clean(ins.get('policyNumber')):
            found_policy = ins
            break
            
    # Fallback: check legacy flat fields if array empty
    if not found_policy:
        if clean(expected_policy) in clean(data.get('insurancePolicyNumber')):
             found_policy = {
                 'insuranceCompany': data.get('insuranceCompany'),
                 'insurancePlan': data.get('insurancePlan'),
                 'policyNumber': data.get('insurancePolicyNumber'),
                 'groupNumber': data.get('insuranceGroupNumber')
             }

    if found_policy:
        # Check specific fields
        # Policy Number (Already checked to find it, but assigning points)
        score += 20
        passed_criteria.append("Policy Number found")
        
        # Provider
        actual_provider = found_policy.get('insuranceCompany', found_policy.get('provider', ''))
        if clean(expected_provider) in clean(actual_provider):
            score += 20
            passed_criteria.append("Provider Correct")
        else:
            feedback.append(f"Provider mismatch: Expected '{expected_provider}', got '{actual_provider}'")

        # Plan Name
        actual_plan = found_policy.get('insurancePlan', found_policy.get('planName', ''))
        if clean(expected_plan) in clean(actual_plan):
            score += 20
            passed_criteria.append("Plan Name Correct")
        else:
            feedback.append(f"Plan Name mismatch: Expected '{expected_plan}', got '{actual_plan}'")

        # Group Number
        actual_group = found_policy.get('groupNumber', '')
        if clean(expected_group) in clean(actual_group):
            score += 20
            passed_criteria.append("Group Number Correct")
        else:
            feedback.append(f"Group Number mismatch: Expected '{expected_group}', got '{actual_group}'")
    else:
        feedback.append(f"Insurance policy '{expected_policy}' not found in patient record.")

    # 3. Data Integrity Check (Prevent overwriting Name/DOB)
    # If these changed, it's a critical failure (maybe they edited the wrong patient)
    actual_first = data.get('firstName', '')
    actual_last = data.get('lastName', '')
    actual_dob = data.get('dateOfBirth', '')
    
    # Simple check for Name (Lucas Silva)
    if "Lucas" not in actual_first or "Silva" not in actual_last:
        score = 0
        feedback.append("CRITICAL: Patient name appears to have been changed or wrong patient modified.")
    elif expected_dob not in str(actual_dob):
         # Allow score but penalize
         score = max(0, score - 20)
         feedback.append(f"Warning: Patient Date of Birth was altered (Expected {expected_dob}, got {actual_dob}).")
    
    # Pass logic
    # Need at least 80 points (Record mod + Policy # + 2 other fields correct)
    is_passing = score >= 80

    return {
        "passed": is_passing,
        "score": score,
        "feedback": " | ".join(feedback)
    }