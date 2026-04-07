#!/usr/bin/env python3
"""
Verifier for Register New Patient task in OpenEMR

Verification Strategy:
1. PRIMARY: Database verification via exported JSON
2. SECONDARY: VLM verification of trajectory for workflow confirmation

Scoring (100 points):
- Patient record exists with correct name: 25 points
- DOB correct: 15 points
- Sex correct: 10 points
- Address correct (street, city, state, postal): 15 points
- Phone correct: 10 points
- Email correct: 10 points
- Created during task execution (anti-gaming): 15 points

Pass threshold: 70 points with patient record existing
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_phone(phone: str) -> str:
    """Extract digits only from phone number for comparison."""
    if not phone:
        return ""
    return re.sub(r'\D', '', phone)


def normalize_string(s: str) -> str:
    """Normalize string for flexible comparison."""
    if not s:
        return ""
    return s.strip().lower()


def check_state_match(actual: str, expected: str) -> bool:
    """Check if state matches (handles abbreviations)."""
    actual_norm = normalize_string(actual)
    expected_norm = normalize_string(expected)
    
    # Direct match
    if actual_norm == expected_norm:
        return True
    
    # Common state abbreviations
    state_abbrevs = {
        "massachusetts": "ma",
        "ma": "massachusetts"
    }
    
    # Check abbreviation match
    if actual_norm in state_abbrevs:
        if state_abbrevs[actual_norm] == expected_norm:
            return True
    if expected_norm in state_abbrevs:
        if state_abbrevs[expected_norm] == actual_norm:
            return True
    
    return False


def check_sex_match(actual: str, expected: str) -> bool:
    """Check if sex matches (handles various formats)."""
    actual_norm = normalize_string(actual)
    expected_norm = normalize_string(expected)
    
    # Direct match
    if actual_norm == expected_norm:
        return True
    
    # Handle abbreviations
    male_variants = ["male", "m"]
    female_variants = ["female", "f"]
    
    if expected_norm in male_variants:
        return actual_norm in male_variants
    if expected_norm in female_variants:
        return actual_norm in female_variants
    
    return False


def verify_register_new_patient(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a new patient was registered with correct information.
    
    Uses copy_from_env to retrieve exported results from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected = {
        "fname": metadata.get('expected_fname', 'Marcus'),
        "lname": metadata.get('expected_lname', 'Wellington'),
        "dob": metadata.get('expected_dob', '1978-11-23'),
        "sex": metadata.get('expected_sex', 'Male'),
        "street": metadata.get('expected_street', '742 Evergreen Terrace'),
        "city": metadata.get('expected_city', 'Springfield'),
        "state": metadata.get('expected_state', 'Massachusetts'),
        "postal": metadata.get('expected_postal', '01103'),
        "phone": metadata.get('expected_phone', '413-555-0199'),
        "email": metadata.get('expected_email', 'marcus.wellington@email.test')
    }
    
    expected_phone_normalized = normalize_phone(expected["phone"])
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/register_new_patient_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "patient_exists": False,
            "dob_correct": False,
            "sex_correct": False,
            "address_correct": False,
            "phone_correct": False,
            "email_correct": False,
            "created_during_task": False
        }
        
        # Extract data from result
        patient_found = result.get('patient_found', False)
        created_during_task = result.get('created_during_task', False)
        patient = result.get('patient', {})
        initial_count = result.get('initial_patient_count', 0)
        current_count = result.get('current_patient_count', 0)
        task_start = result.get('task_start_timestamp', 0)
        
        logger.info(f"Result: found={patient_found}, created_during_task={created_during_task}")
        logger.info(f"Patient data: {patient}")
        
        # CRITERION 1: Patient exists with correct name (25 points)
        if patient_found:
            actual_fname = patient.get('fname', '')
            actual_lname = patient.get('lname', '')
            
            if (normalize_string(actual_fname) == normalize_string(expected["fname"]) and
                normalize_string(actual_lname) == normalize_string(expected["lname"])):
                score += 25
                subscores["patient_exists"] = True
                feedback_parts.append(f"✅ Patient '{expected['fname']} {expected['lname']}' found in database")
            else:
                feedback_parts.append(f"❌ Name mismatch: expected '{expected['fname']} {expected['lname']}', got '{actual_fname} {actual_lname}'")
        else:
            feedback_parts.append(f"❌ Patient '{expected['fname']} {expected['lname']}' NOT found in database")
            
            # Check if any new patients were added
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} new patient(s) added but not with expected name")
            else:
                feedback_parts.append("No new patients were added to the database")
            
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: DOB correct (15 points)
        actual_dob = patient.get('dob', '')
        if actual_dob == expected["dob"]:
            score += 15
            subscores["dob_correct"] = True
            feedback_parts.append(f"✅ DOB correct: {expected['dob']}")
        else:
            feedback_parts.append(f"❌ DOB incorrect: expected {expected['dob']}, got {actual_dob}")
        
        # CRITERION 3: Sex correct (10 points)
        actual_sex = patient.get('sex', '')
        if check_sex_match(actual_sex, expected["sex"]):
            score += 10
            subscores["sex_correct"] = True
            feedback_parts.append(f"✅ Sex correct: {expected['sex']}")
        else:
            feedback_parts.append(f"❌ Sex incorrect: expected {expected['sex']}, got {actual_sex}")
        
        # CRITERION 4: Address correct (15 points - proportional)
        address_score = 0
        address_max = 15
        address_fields = 4  # street, city, state, postal
        
        # Street
        actual_street = patient.get('street', '')
        if normalize_string(actual_street) == normalize_string(expected["street"]):
            address_score += address_max / address_fields
            feedback_parts.append(f"✅ Street correct")
        else:
            feedback_parts.append(f"❌ Street: expected '{expected['street']}', got '{actual_street}'")
        
        # City
        actual_city = patient.get('city', '')
        if normalize_string(actual_city) == normalize_string(expected["city"]):
            address_score += address_max / address_fields
            feedback_parts.append(f"✅ City correct")
        else:
            feedback_parts.append(f"❌ City: expected '{expected['city']}', got '{actual_city}'")
        
        # State
        actual_state = patient.get('state', '')
        if check_state_match(actual_state, expected["state"]):
            address_score += address_max / address_fields
            feedback_parts.append(f"✅ State correct")
        else:
            feedback_parts.append(f"❌ State: expected '{expected['state']}', got '{actual_state}'")
        
        # Postal code
        actual_postal = patient.get('postal_code', '')
        # Normalize postal codes (handle formats like "01103" vs "01103-0000")
        if actual_postal.startswith(expected["postal"]) or expected["postal"].startswith(actual_postal.split('-')[0]):
            address_score += address_max / address_fields
            feedback_parts.append(f"✅ Postal code correct")
        else:
            feedback_parts.append(f"❌ Postal: expected '{expected['postal']}', got '{actual_postal}'")
        
        score += int(address_score)
        if address_score >= address_max * 0.75:  # At least 3 of 4 fields correct
            subscores["address_correct"] = True
        
        # CRITERION 5: Phone correct (10 points)
        actual_phone = patient.get('phone_cell', '')
        actual_phone_normalized = patient.get('phone_normalized', normalize_phone(actual_phone))
        
        if actual_phone_normalized == expected_phone_normalized:
            score += 10
            subscores["phone_correct"] = True
            feedback_parts.append(f"✅ Phone correct: {expected['phone']}")
        else:
            feedback_parts.append(f"❌ Phone: expected '{expected['phone']}' ({expected_phone_normalized}), got '{actual_phone}' ({actual_phone_normalized})")
        
        # CRITERION 6: Email correct (10 points)
        actual_email = patient.get('email', '')
        if normalize_string(actual_email) == normalize_string(expected["email"]):
            score += 10
            subscores["email_correct"] = True
            feedback_parts.append(f"✅ Email correct")
        else:
            feedback_parts.append(f"❌ Email: expected '{expected['email']}', got '{actual_email}'")
        
        # CRITERION 7: Created during task (anti-gaming) (15 points)
        if created_during_task:
            score += 15
            subscores["created_during_task"] = True
            feedback_parts.append(f"✅ Patient created during task execution")
        else:
            patient_ts = patient.get('created_timestamp', 0)
            feedback_parts.append(f"⚠️ Patient may have existed before task (created_ts={patient_ts}, task_start={task_start})")
        
        # Determine pass/fail
        # Must have: patient exists (25) + created during task (15) = 40 minimum
        # Plus at least 30 more points from other criteria for 70 total
        key_criteria_met = subscores["patient_exists"] and subscores["created_during_task"]
        passed = score >= 70 and key_criteria_met
        
        # If patient exists but not created during task, cap score and fail
        if subscores["patient_exists"] and not subscores["created_during_task"]:
            feedback_parts.append("⚠️ Anti-gaming check failed: patient record may not have been created during this task")
            passed = False
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "expected": expected,
                "actual": patient,
                "initial_count": initial_count,
                "current_count": current_count
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found in container")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Export result file not found - task may not have completed properly",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {}
        }


# Optional: VLM-based trajectory verification for additional confidence
def verify_with_vlm(traj: Dict[str, Any], env_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Secondary VLM verification using trajectory frames.
    
    Checks that the agent actually navigated through the patient registration workflow.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        query_vlm = env_info.get('query_vlm')
        if not query_vlm:
            return {"success": False, "error": "VLM not available"}
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "error": "No screenshots available"}
        
        all_images = frames + ([final] if final else [])
        
        prompt = """Analyze these screenshots from an OpenEMR session where the user was asked to register a new patient named Marcus Wellington.

Look for evidence of:
1. Navigating to Patient menu or New Patient screen
2. A patient registration form being filled out
3. Patient name fields showing "Marcus" and "Wellington"
4. Form submission or save action
5. Success confirmation or patient chart opening

For each screenshot, describe what you see related to patient registration.
Then provide an overall assessment:

{
    "saw_patient_menu": true/false,
    "saw_registration_form": true/false,
    "saw_patient_name_entered": true/false,
    "saw_save_or_submit": true/false,
    "saw_success_confirmation": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
        
        result = query_vlm(prompt=prompt, images=all_images)
        return result
        
    except ImportError:
        return {"success": False, "error": "VLM module not available"}
    except Exception as e:
        return {"success": False, "error": str(e)}