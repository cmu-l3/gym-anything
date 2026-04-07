#!/usr/bin/env python3
"""
Verifier for Create Cardiology Referral task in OpenEMR

MULTI-SIGNAL VERIFICATION:
1. Referral record exists in transactions table (30 points)
2. Referral is for correct patient - Jayson Fadel pid=3 (20 points)
3. Refer_to field contains cardiology-related term (20 points)
4. Diagnosis/reason mentions hypertension/HTN/BP (15 points)
5. Referral date is valid (10 points)
6. Referral was newly created during task (5 points)

Pass threshold: 70 points with referral_exists AND correct_patient
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cardiology_referral(traj, env_info, task_info):
    """
    Verify that a cardiology referral was correctly created for the hypertensive patient.
    
    Uses copy_from_env to read pre-exported verification data from the container.
    The export_result.sh script queries the database and saves results to JSON.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    
    # Keywords to look for
    cardio_keywords = metadata.get('expected_refer_to_keywords', ['cardio', 'heart', 'cardiovascular'])
    reason_keywords = metadata.get('expected_reason_keywords', ['hypertension', 'htn', 'blood pressure', 'bp'])
    
    # Scoring weights from metadata
    score_referral_exists = metadata.get('score_referral_exists', 30)
    score_correct_patient = metadata.get('score_correct_patient', 20)
    score_cardiology = metadata.get('score_cardiology_specified', 20)
    score_hypertension = metadata.get('score_hypertension_documented', 15)
    score_date = metadata.get('score_valid_date', 10)
    score_new = metadata.get('score_newly_created', 5)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/cardiology_referral_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "referral_exists": False,
            "correct_patient": False,
            "cardiology_specified": False,
            "hypertension_documented": False,
            "date_valid": False,
            "newly_created": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_referral_count', 0)
        current_count = result.get('current_referral_count', 0)
        referral_found = result.get('referral_found', False)
        is_new_referral = result.get('is_new_referral', False)
        referral = result.get('referral', {})
        validation = result.get('validation', {})
        
        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"Referral found: {referral_found}, is_new: {is_new_referral}")
        logger.info(f"Referral details: {referral}")
        
        # ================================================================
        # CRITERION 1: Referral record exists (30 points)
        # ================================================================
        if referral_found:
            score += score_referral_exists
            subscores["referral_exists"] = True
            feedback_parts.append(f"Referral record found (id={referral.get('id', 'unknown')})")
        else:
            feedback_parts.append("No referral record found for patient")
            # Early return - nothing else to check
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {"reason": "No referral created"}
            }
        
        # ================================================================
        # CRITERION 2: Correct patient (20 points)
        # This is critical - referral must be for Jayson Fadel (pid=3)
        # ================================================================
        referral_pid = referral.get('pid', '')
        try:
            referral_pid_int = int(referral_pid) if referral_pid else 0
        except (ValueError, TypeError):
            referral_pid_int = 0
        
        if referral_pid_int == expected_pid:
            score += score_correct_patient
            subscores["correct_patient"] = True
            feedback_parts.append(f"Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"WRONG PATIENT: expected pid={expected_pid}, got {referral_pid}")
            # Adversarial case: wrong patient is a critical failure
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {"reason": "Referral for wrong patient"}
            }
        
        # ================================================================
        # CRITERION 3: Cardiology specified in refer_to field (20 points)
        # ================================================================
        refer_to = referral.get('refer_to', '').lower()
        cardiology_found = any(kw.lower() in refer_to for kw in cardio_keywords)
        
        if cardiology_found or validation.get('refer_to_valid', False):
            score += score_cardiology
            subscores["cardiology_specified"] = True
            feedback_parts.append(f"Cardiology referral specified: '{referral.get('refer_to', '')}'")
        else:
            feedback_parts.append(f"Refer_to does not mention cardiology: '{referral.get('refer_to', '')}'")
        
        # ================================================================
        # CRITERION 4: Hypertension documented in reason/diagnosis (15 points)
        # ================================================================
        diagnosis = referral.get('diagnosis', '').lower()
        body = referral.get('body', '').lower()
        combined_reason = f"{diagnosis} {body}"
        
        hypertension_found = any(kw.lower() in combined_reason for kw in reason_keywords)
        
        if hypertension_found or validation.get('reason_valid', False):
            score += score_hypertension
            subscores["hypertension_documented"] = True
            feedback_parts.append("Hypertension/HTN mentioned in referral reason")
        else:
            feedback_parts.append(f"Reason does not mention hypertension: '{referral.get('diagnosis', '')}'")
        
        # ================================================================
        # CRITERION 5: Valid referral date (10 points)
        # ================================================================
        refer_date = referral.get('refer_date', '')
        
        if validation.get('date_valid', False):
            score += score_date
            subscores["date_valid"] = True
            feedback_parts.append(f"Valid referral date: {refer_date}")
        elif refer_date and refer_date not in ['', 'NULL', '0000-00-00', None]:
            # Verify date ourselves
            try:
                ref_date = datetime.strptime(refer_date, '%Y-%m-%d').date()
                today = datetime.now().date()
                yesterday = today - timedelta(days=1)
                max_date = today + timedelta(days=30)
                
                if yesterday <= ref_date <= max_date:
                    score += score_date
                    subscores["date_valid"] = True
                    feedback_parts.append(f"Valid referral date: {refer_date}")
                else:
                    feedback_parts.append(f"Referral date out of range: {refer_date}")
            except ValueError:
                feedback_parts.append(f"Invalid date format: {refer_date}")
        else:
            feedback_parts.append("No referral date specified")
        
        # ================================================================
        # CRITERION 6: Newly created during task (5 points) - Anti-gaming
        # ================================================================
        if is_new_referral:
            score += score_new
            subscores["newly_created"] = True
            feedback_parts.append(f"New referral created (count: {initial_count} -> {current_count})")
        elif current_count > initial_count:
            # Backup check: count increased
            score += score_new
            subscores["newly_created"] = True
            feedback_parts.append(f"New referral detected by count increase")
        else:
            feedback_parts.append("Referral may have existed before task (not newly created)")
        
        # ================================================================
        # CALCULATE FINAL RESULT
        # ================================================================
        max_score = score_referral_exists + score_correct_patient + score_cardiology + score_hypertension + score_date + score_new
        
        # Pass requires: referral exists + correct patient + at least partial content match
        key_criteria_met = (
            subscores["referral_exists"] and 
            subscores["correct_patient"] and
            (subscores["cardiology_specified"] or subscores["hypertension_documented"])
        )
        
        # Need 70% score AND key criteria
        passed = score >= 70 and key_criteria_met
        
        # Bonus feedback for perfect score
        if score >= 95:
            feedback_parts.append("Excellent! Complete and correct cardiology referral created.")
        elif score >= 70:
            feedback_parts.append("Good referral created with most required elements.")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "referral_id": referral.get('id'),
                "refer_to": referral.get('refer_to'),
                "diagnosis": referral.get('diagnosis'),
                "refer_date": referral.get('refer_date'),
                "patient_pid": referral_pid,
                "is_new": is_new_referral
            }
        }
        
    except FileNotFoundError as e:
        logger.error(f"Result file not found: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found - export_result.sh may have failed",
            "subscores": {
                "referral_exists": False,
                "correct_patient": False,
                "cardiology_specified": False,
                "hypertension_documented": False,
                "date_valid": False,
                "newly_created": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {
                "referral_exists": False,
                "correct_patient": False,
                "cardiology_specified": False,
                "hypertension_documented": False,
                "date_valid": False,
                "newly_created": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}",
            "subscores": {
                "referral_exists": False,
                "correct_patient": False,
                "cardiology_specified": False,
                "hypertension_documented": False,
                "date_valid": False,
                "newly_created": False
            }
        }


# For standalone testing
if __name__ == "__main__":
    # Mock test
    print("Cardiology Referral Verifier - Standalone Test")
    print("This verifier expects /tmp/cardiology_referral_result.json from export_result.sh")
    
    # Test with mock data
    mock_result = {
        "patient_pid": 3,
        "initial_referral_count": 0,
        "current_referral_count": 1,
        "referral_found": True,
        "is_new_referral": True,
        "referral": {
            "id": "1",
            "pid": "3",
            "refer_to": "Cardiology",
            "diagnosis": "Hypertension evaluation",
            "refer_date": datetime.now().strftime("%Y-%m-%d"),
            "risk_level": "Low"
        },
        "validation": {
            "refer_to_valid": True,
            "reason_valid": True,
            "date_valid": True
        }
    }
    
    print(f"Mock result would score well if properly formatted")
    print(f"Expected pass criteria: referral_exists + correct_patient + (cardiology OR hypertension)")