#!/usr/bin/env python3
"""
Verifier for Create Patient Encounter task in OpenEMR

ROBUST MULTI-SIGNAL VERIFICATION:
1. Login successful (implicit from data access): 10 points
2. Patient located (encounter linked to correct pid): 15 points  
3. Encounter created (new encounter in database): 35 points
4. Correct patient link (pid matches expected): 15 points
5. Valid date (today or recent): 10 points
6. Reason documented (contains back/pain keywords): 15 points

Pass threshold: 75 points with encounter_created criterion met

Anti-gaming measures:
- Verifies encounter ID is higher than initial max ID
- Checks encounter count increased
- Validates timestamps
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


def verify_create_patient_encounter(traj, env_info, task_info):
    """
    Verify that a new clinical encounter was created for the specified patient.
    
    Uses copy_from_env to read pre-exported verification data from the container.
    The export_result.sh script queries the database and saves results to JSON.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available - cannot verify task"
        }
    
    # Get expected values from task_info metadata (with defaults)
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    reason_keywords = metadata.get('expected_reason_keywords', ['back', 'pain', 'lower'])
    min_score = metadata.get('min_score_to_pass', 75)
    
    # Scoring weights from metadata
    scoring = metadata.get('scoring', {})
    SCORE_LOGIN = scoring.get('login_success', 10)
    SCORE_PATIENT_LOCATED = scoring.get('patient_located', 15)
    SCORE_ENCOUNTER_CREATED = scoring.get('encounter_created', 35)
    SCORE_CORRECT_PATIENT = scoring.get('correct_patient', 15)
    SCORE_VALID_DATE = scoring.get('valid_date', 10)
    SCORE_REASON = scoring.get('reason_documented', 15)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_encounter_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "login_success": False,
            "patient_located": False,
            "encounter_created": False,
            "correct_patient": False,
            "valid_date": False,
            "reason_documented": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_encounter_count', 0)
        current_count = result.get('current_encounter_count', 0)
        highest_initial_id = result.get('highest_initial_encounter_id', 0)
        encounter_found = result.get('encounter_found', False)
        is_new_encounter = result.get('is_new_encounter', False)
        encounter = result.get('encounter', {})
        validation = result.get('validation', {})
        environment = result.get('environment', {})
        
        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, "
                   f"current={current_count}, found={encounter_found}, new={is_new_encounter}")
        logger.info(f"Encounter data: {encounter}")
        
        # ================================================================
        # CRITERION 1: Login Success (10 points)
        # Implicit - if we got valid data from database, login was successful
        # ================================================================
        firefox_running = environment.get('firefox_running', False)
        if current_count >= 0 and firefox_running:
            score += SCORE_LOGIN
            subscores["login_success"] = True
            feedback_parts.append("Login successful (application accessed)")
        elif current_count >= 0:
            score += SCORE_LOGIN // 2  # Partial credit
            feedback_parts.append("Database accessible (login likely successful)")
        else:
            feedback_parts.append("Could not verify login status")
        
        # ================================================================
        # CRITERION 2: Encounter Created (35 points) - KEY CRITERION
        # Must have a NEW encounter (higher ID than initial max)
        # ================================================================
        encounter_id_str = encounter.get('id', '0')
        try:
            encounter_id = int(encounter_id_str) if encounter_id_str else 0
        except (ValueError, TypeError):
            encounter_id = 0
        
        if is_new_encounter and encounter_id > highest_initial_id:
            score += SCORE_ENCOUNTER_CREATED
            subscores["encounter_created"] = True
            feedback_parts.append(f"New encounter created (ID: {encounter_id}, previous max: {highest_initial_id})")
        elif current_count > initial_count:
            # Encounter count increased but ID check failed - partial credit
            score += SCORE_ENCOUNTER_CREATED // 2
            subscores["encounter_created"] = True  # Still counts as created
            feedback_parts.append(f"Encounter count increased ({initial_count} → {current_count})")
        else:
            feedback_parts.append(f"No new encounter detected (count: {initial_count} → {current_count})")
            # Early exit with detailed feedback
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | CRITICAL: No encounter was created",
                "subscores": subscores,
                "details": {
                    "initial_count": initial_count,
                    "current_count": current_count,
                    "highest_initial_id": highest_initial_id,
                    "encounter_id": encounter_id
                }
            }
        
        # ================================================================
        # CRITERION 3: Correct Patient Link (15 points)
        # Encounter must be linked to expected patient (pid=3)
        # ================================================================
        encounter_pid_str = encounter.get('pid', '0')
        try:
            encounter_pid = int(encounter_pid_str) if encounter_pid_str else 0
        except (ValueError, TypeError):
            encounter_pid = 0
        
        if encounter_pid == expected_pid:
            score += SCORE_CORRECT_PATIENT
            subscores["correct_patient"] = True
            feedback_parts.append(f"Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"WRONG patient! Expected pid={expected_pid}, got pid={encounter_pid}")
            # This is a significant error - reduce overall score potential
        
        # ================================================================
        # CRITERION 4: Patient Located (15 points)
        # Implicitly verified if encounter was created for correct patient
        # ================================================================
        if subscores["encounter_created"] and subscores["correct_patient"]:
            score += SCORE_PATIENT_LOCATED
            subscores["patient_located"] = True
            feedback_parts.append("Patient successfully located and selected")
        elif subscores["encounter_created"]:
            score += SCORE_PATIENT_LOCATED // 2  # Partial - encounter created but wrong patient
            feedback_parts.append("Patient search occurred (encounter created)")
        
        # ================================================================
        # CRITERION 5: Valid Date (10 points)
        # Encounter date should be today or very recent
        # ================================================================
        encounter_date = encounter.get('date', '')
        date_valid = validation.get('date_valid', False)
        
        if date_valid:
            score += SCORE_VALID_DATE
            subscores["valid_date"] = True
            feedback_parts.append(f"Valid encounter date ({encounter_date})")
        elif encounter_date:
            # Check ourselves
            try:
                enc_date = datetime.strptime(encounter_date, '%Y-%m-%d').date()
                today = datetime.now().date()
                if enc_date >= today - timedelta(days=1) and enc_date <= today + timedelta(days=1):
                    score += SCORE_VALID_DATE
                    subscores["valid_date"] = True
                    feedback_parts.append(f"Encounter date valid ({encounter_date})")
                else:
                    score += SCORE_VALID_DATE // 2  # Partial credit for having a date
                    feedback_parts.append(f"Encounter date may be incorrect ({encounter_date}, expected {today})")
            except ValueError:
                feedback_parts.append(f"Could not parse encounter date: {encounter_date}")
        else:
            feedback_parts.append("No encounter date found")
        
        # ================================================================
        # CRITERION 6: Reason Documented (15 points)
        # Must contain keywords related to back pain
        # ================================================================
        encounter_reason = encounter.get('reason', '')
        reason_valid = validation.get('reason_valid', False)
        
        if reason_valid:
            score += SCORE_REASON
            subscores["reason_documented"] = True
            feedback_parts.append(f"Reason properly documented: '{encounter_reason[:50]}...' " if len(encounter_reason) > 50 else f"Reason properly documented: '{encounter_reason}'")
        elif encounter_reason:
            # Check ourselves for keywords
            reason_lower = encounter_reason.lower()
            keywords_found = [kw for kw in reason_keywords if kw.lower() in reason_lower]
            if keywords_found:
                score += SCORE_REASON
                subscores["reason_documented"] = True
                feedback_parts.append(f"Reason contains keywords {keywords_found}: '{encounter_reason}'")
            else:
                score += SCORE_REASON // 3  # Minimal credit for having any reason
                feedback_parts.append(f"Reason documented but missing expected keywords: '{encounter_reason}'")
        else:
            feedback_parts.append("No encounter reason documented")
        
        # ================================================================
        # Calculate final result
        # ================================================================
        max_score = SCORE_LOGIN + SCORE_PATIENT_LOCATED + SCORE_ENCOUNTER_CREATED + \
                   SCORE_CORRECT_PATIENT + SCORE_VALID_DATE + SCORE_REASON
        
        # Passing requires: score >= threshold AND encounter was created
        key_criterion_met = subscores["encounter_created"]
        passed = score >= min_score and key_criterion_met
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        if passed:
            feedback = f"SUCCESS: {feedback}"
        else:
            if not key_criterion_met:
                feedback = f"FAILED (no encounter created): {feedback}"
            else:
                feedback = f"FAILED (score {score}/{max_score} < {min_score}): {feedback}"
        
        return {
            "passed": passed,
            "score": score,
            "max_score": max_score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "expected_pid": expected_pid,
                "encounter_id": encounter_id,
                "encounter_date": encounter_date,
                "encounter_reason": encounter_reason,
                "initial_count": initial_count,
                "current_count": current_count,
                "is_new_encounter": is_new_encounter
            }
        }
        
    except FileNotFoundError as e:
        logger.error(f"Result file not found: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found - export may have failed: {e}",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


# For standalone testing
if __name__ == "__main__":
    import subprocess
    
    def mock_copy(src, dst):
        """Mock copy function for testing"""
        subprocess.run(["cp", src, dst], check=True)
    
    # Test with mock data
    test_env_info = {"copy_from_env": mock_copy}
    test_task_info = {
        "metadata": {
            "patient_pid": 3,
            "patient_fname": "Jayson",
            "patient_lname": "Fadel",
            "expected_reason_keywords": ["back", "pain", "lower"]
        }
    }
    
    result = verify_create_patient_encounter({}, test_env_info, test_task_info)
    print(f"\nVerification Result:")
    print(f"  Passed: {result['passed']}")
    print(f"  Score: {result['score']}")
    print(f"  Feedback: {result['feedback']}")
    print(f"  Subscores: {result.get('subscores', {})}")