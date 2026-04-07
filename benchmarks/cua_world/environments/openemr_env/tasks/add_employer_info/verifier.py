#!/usr/bin/env python3
"""
Verifier for Add Employer Information task in OpenEMR

Verifies that employer information was correctly added to a patient's record.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring:
- Employer record exists: 25 points
- Employer name correct: 25 points  
- Street address correct: 15 points
- City/State correct: 20 points
- Postal code correct: 10 points
- Created after task start: 5 points

Pass threshold: 70 points (requires employer exists + name + city/state minimum)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_string(s):
    """Normalize string for comparison - lowercase, strip whitespace, remove extra spaces."""
    if not s:
        return ""
    return re.sub(r'\s+', ' ', str(s).lower().strip())


def fuzzy_match(expected, actual, threshold=0.8):
    """Check if actual contains most of the expected string."""
    if not expected or not actual:
        return False
    
    expected_norm = normalize_string(expected)
    actual_norm = normalize_string(actual)
    
    # Exact match
    if expected_norm == actual_norm:
        return True
    
    # Check if expected is contained in actual or vice versa
    if expected_norm in actual_norm or actual_norm in expected_norm:
        return True
    
    # Word-based matching
    expected_words = set(expected_norm.split())
    actual_words = set(actual_norm.split())
    
    if not expected_words:
        return False
    
    # Check overlap
    overlap = len(expected_words & actual_words) / len(expected_words)
    return overlap >= threshold


def verify_add_employer_info(traj, env_info, task_info):
    """
    Verify that employer information was correctly added to the patient record.
    
    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info including copy_from_env function
        task_info: Task configuration including metadata with expected values
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('employer_name', 'Precision Manufacturing LLC')
    expected_street = metadata.get('employer_street', '2750 Commerce Boulevard')
    expected_city = metadata.get('employer_city', 'Worcester')
    expected_state = metadata.get('employer_state', 'MA')
    expected_postal = metadata.get('employer_postal', '01608')
    expected_country = metadata.get('employer_country', 'USA')
    
    # Get scoring weights from metadata
    scoring = metadata.get('scoring', {})
    pts_employer_exists = scoring.get('employer_exists', 25)
    pts_name_correct = scoring.get('name_correct', 25)
    pts_street_correct = scoring.get('street_correct', 15)
    pts_city_state_correct = scoring.get('city_state_correct', 20)
    pts_postal_correct = scoring.get('postal_correct', 10)
    pts_timestamp_valid = scoring.get('timestamp_valid', 5)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_employer_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "employer_exists": False,
            "name_correct": False,
            "street_correct": False,
            "city_state_correct": False,
            "postal_correct": False,
            "timestamp_valid": False
        }
        
        # Extract data from result
        employer_found = result.get('employer_found', False)
        new_employer_created = result.get('new_employer_created', False)
        employer = result.get('employer', {})
        patient = result.get('patient', {})
        task_start = result.get('task_start_timestamp', 0)
        initial_count = result.get('initial_employer_count', 0)
        current_count = result.get('current_employer_count', 0)
        patient_employer_id = result.get('patient_employer_id', '')
        
        logger.info(f"Result data: found={employer_found}, new={new_employer_created}")
        logger.info(f"Employer data: {employer}")
        logger.info(f"Patient: {patient}")
        
        # CRITERION 1: Employer record exists (25 points)
        if employer_found:
            score += pts_employer_exists
            subscores["employer_exists"] = True
            feedback_parts.append(f"✅ Employer record found (ID: {employer.get('id', 'N/A')})")
        else:
            feedback_parts.append("❌ No employer record found for patient")
            # No employer - can't continue verification
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {
                    "patient": patient,
                    "initial_count": initial_count,
                    "current_count": current_count
                }
            }
        
        # CRITERION 2: Employer name correct (25 points)
        actual_name = employer.get('name', '')
        if fuzzy_match(expected_name, actual_name):
            score += pts_name_correct
            subscores["name_correct"] = True
            feedback_parts.append(f"✅ Employer name correct: {actual_name}")
        else:
            # Partial credit for containing key words
            name_lower = normalize_string(actual_name)
            if 'precision' in name_lower or 'manufacturing' in name_lower:
                score += pts_name_correct // 2
                feedback_parts.append(f"⚠️ Employer name partially correct: '{actual_name}' (expected: '{expected_name}')")
            else:
                feedback_parts.append(f"❌ Employer name incorrect: '{actual_name}' (expected: '{expected_name}')")
        
        # CRITERION 3: Street address correct (15 points)
        actual_street = employer.get('street', '')
        if fuzzy_match(expected_street, actual_street):
            score += pts_street_correct
            subscores["street_correct"] = True
            feedback_parts.append(f"✅ Street address correct: {actual_street}")
        else:
            # Partial credit for containing key words
            street_lower = normalize_string(actual_street)
            if '2750' in street_lower or 'commerce' in street_lower:
                score += pts_street_correct // 2
                feedback_parts.append(f"⚠️ Street address partially correct: '{actual_street}'")
            else:
                feedback_parts.append(f"❌ Street address incorrect: '{actual_street}' (expected: '{expected_street}')")
        
        # CRITERION 4: City and State correct (20 points)
        actual_city = employer.get('city', '')
        actual_state = employer.get('state', '')
        
        city_match = fuzzy_match(expected_city, actual_city)
        state_match = normalize_string(actual_state) == normalize_string(expected_state)
        
        if city_match and state_match:
            score += pts_city_state_correct
            subscores["city_state_correct"] = True
            feedback_parts.append(f"✅ City/State correct: {actual_city}, {actual_state}")
        elif city_match:
            score += pts_city_state_correct // 2
            feedback_parts.append(f"⚠️ City correct ({actual_city}) but state incorrect ({actual_state}, expected: {expected_state})")
        elif state_match:
            score += pts_city_state_correct // 2
            feedback_parts.append(f"⚠️ State correct ({actual_state}) but city incorrect ({actual_city}, expected: {expected_city})")
        else:
            feedback_parts.append(f"❌ City/State incorrect: '{actual_city}, {actual_state}' (expected: '{expected_city}, {expected_state}')")
        
        # CRITERION 5: Postal code correct (10 points)
        actual_postal = employer.get('postal_code', '')
        if normalize_string(actual_postal) == normalize_string(expected_postal):
            score += pts_postal_correct
            subscores["postal_correct"] = True
            feedback_parts.append(f"✅ Postal code correct: {actual_postal}")
        else:
            # Partial credit if close
            if actual_postal and actual_postal.startswith(expected_postal[:3]):
                score += pts_postal_correct // 2
                feedback_parts.append(f"⚠️ Postal code partially correct: '{actual_postal}' (expected: '{expected_postal}')")
            else:
                feedback_parts.append(f"❌ Postal code incorrect: '{actual_postal}' (expected: '{expected_postal}')")
        
        # CRITERION 6: Created during task (anti-gaming) (5 points)
        if new_employer_created or current_count > initial_count:
            score += pts_timestamp_valid
            subscores["timestamp_valid"] = True
            feedback_parts.append(f"✅ Employer record created during task (count: {initial_count} -> {current_count})")
        else:
            # Check if employer was associated (even if record existed)
            if patient_employer_id and patient_employer_id != "NULL" and patient_employer_id != "":
                score += pts_timestamp_valid // 2
                feedback_parts.append(f"⚠️ Employer associated but may not be newly created")
            else:
                feedback_parts.append(f"⚠️ Could not verify employer was created during task")
        
        # Determine pass/fail
        # Must have employer exists + name correct + city/state correct minimum (70 points)
        key_criteria_met = (
            subscores["employer_exists"] and 
            subscores["name_correct"] and 
            subscores["city_state_correct"]
        )
        
        passed = score >= 70 and key_criteria_met
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient": patient,
                "employer": employer,
                "expected": {
                    "name": expected_name,
                    "street": expected_street,
                    "city": expected_city,
                    "state": expected_state,
                    "postal": expected_postal
                },
                "counts": {
                    "initial": initial_count,
                    "current": current_count
                }
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Verification data not found - export_result.sh may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse verification data: {e}",
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