#!/usr/bin/env python3
"""
Verifier for Set Preferred Pharmacy task in OpenEMR

Verifies that the agent correctly updated a patient's preferred pharmacy.

Scoring (100 points total):
- Patient record accessed (correct patient): 15 points
- Demographics/pharmacy section navigated: 20 points
- Pharmacy selection made (any pharmacy linked): 25 points
- Correct pharmacy linked (CVS Pharmacy - Downtown): 30 points
- Change persisted in database: 10 points

Passing threshold: 70 points with correct pharmacy linked
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_set_preferred_pharmacy(traj, env_info, task_info):
    """
    Verify that the preferred pharmacy was correctly set for the patient.
    
    Uses copy_from_env to read exported result data from the container.
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
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Antonia')
    expected_lname = metadata.get('patient_lname', 'Gottlieb')
    target_pharmacy_id = metadata.get('target_pharmacy_id', 50)
    target_pharmacy_name = metadata.get('target_pharmacy_name', 'CVS Pharmacy - Downtown')
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/set_pharmacy_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "pharmacy_changed": False,
            "any_pharmacy_linked": False,
            "correct_pharmacy": False,
            "change_persisted": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_pharmacy = result.get('initial_pharmacy_id', 'NULL')
        current_pharmacy = result.get('current_pharmacy_id', 'NULL')
        pharmacy_found = result.get('pharmacy_found', False)
        pharmacy_details = result.get('pharmacy_details', {})
        validation = result.get('validation', {})
        timestamps = result.get('timestamps', {})
        
        logger.info(f"Result: pid={patient_pid}, initial={initial_pharmacy}, current={current_pharmacy}")
        logger.info(f"Pharmacy details: {pharmacy_details}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Correct patient (15 points)
        # Verify we're checking the right patient
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✓ Correct patient verified (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient ID: expected {expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Verification error: wrong patient ID in result",
                "subscores": subscores
            }
        
        # CRITERION 2: Pharmacy was changed from initial state (20 points)
        # Anti-gaming: ensure something actually changed
        pharmacy_changed = validation.get('pharmacy_changed', False)
        if pharmacy_changed:
            score += 20
            subscores["pharmacy_changed"] = True
            feedback_parts.append(f"✓ Pharmacy assignment changed (from '{initial_pharmacy}' to '{current_pharmacy}')")
        elif current_pharmacy != 'NULL' and current_pharmacy != initial_pharmacy:
            # Backup check
            score += 20
            subscores["pharmacy_changed"] = True
            feedback_parts.append(f"✓ Pharmacy assignment updated")
        else:
            if current_pharmacy == 'NULL':
                feedback_parts.append("✗ No pharmacy assigned to patient")
            else:
                feedback_parts.append(f"✗ Pharmacy was not changed (still '{current_pharmacy}')")
        
        # CRITERION 3: Any pharmacy is now linked (25 points)
        if current_pharmacy != 'NULL' and current_pharmacy != '' and pharmacy_found:
            score += 25
            subscores["any_pharmacy_linked"] = True
            pharmacy_name = pharmacy_details.get('name', 'Unknown')
            feedback_parts.append(f"✓ Pharmacy linked to patient: {pharmacy_name}")
        else:
            feedback_parts.append("✗ No pharmacy linked to patient record")
        
        # CRITERION 4: Correct pharmacy linked (30 points) - CRITICAL
        correct_pharmacy = validation.get('correct_pharmacy', False)
        current_pharmacy_name = pharmacy_details.get('name', '')
        
        # Multiple ways to verify correct pharmacy
        if correct_pharmacy:
            score += 30
            subscores["correct_pharmacy"] = True
            feedback_parts.append(f"✓ Correct pharmacy assigned: {target_pharmacy_name}")
        elif str(current_pharmacy) == str(target_pharmacy_id):
            score += 30
            subscores["correct_pharmacy"] = True
            feedback_parts.append(f"✓ Correct pharmacy ID assigned: {current_pharmacy}")
        elif target_pharmacy_name.lower() in current_pharmacy_name.lower():
            score += 30
            subscores["correct_pharmacy"] = True
            feedback_parts.append(f"✓ Correct pharmacy matched by name: {current_pharmacy_name}")
        elif 'cvs' in current_pharmacy_name.lower() and 'downtown' in current_pharmacy_name.lower():
            score += 30
            subscores["correct_pharmacy"] = True
            feedback_parts.append(f"✓ Correct pharmacy matched: {current_pharmacy_name}")
        else:
            feedback_parts.append(f"✗ Wrong pharmacy: expected '{target_pharmacy_name}' (id={target_pharmacy_id}), got '{current_pharmacy_name}' (id={current_pharmacy})")
        
        # CRITERION 5: Change persisted (10 points)
        # Verify by checking if current state matches expected
        if subscores["correct_pharmacy"] and subscores["pharmacy_changed"]:
            score += 10
            subscores["change_persisted"] = True
            feedback_parts.append("✓ Change persisted in database")
        elif subscores["any_pharmacy_linked"] and subscores["pharmacy_changed"]:
            # Partial credit if any change was made and persisted
            score += 5
            feedback_parts.append("✓ A pharmacy change was persisted (partial credit)")
        
        # Determine pass/fail
        # Must have correct pharmacy to pass
        passed = subscores["correct_pharmacy"] and score >= 70
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})",
                "expected_pharmacy": f"{target_pharmacy_name} (id={target_pharmacy_id})",
                "actual_pharmacy": f"{current_pharmacy_name} (id={current_pharmacy})",
                "initial_pharmacy_id": initial_pharmacy
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found. Export script may have failed or task did not complete."
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result data: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


if __name__ == "__main__":
    # Local testing
    import subprocess
    
    class MockEnvInfo:
        @staticmethod
        def copy_file(src, dst):
            subprocess.run(["cp", src, dst], check=True)
    
    def mock_copy(src, dst):
        subprocess.run(["docker", "cp", f"openemr-mysql:{src}", dst], check=True)
    
    # Create mock task info
    task_info = {
        "metadata": {
            "patient_pid": 5,
            "patient_fname": "Antonia",
            "patient_lname": "Gottlieb",
            "target_pharmacy_id": 50,
            "target_pharmacy_name": "CVS Pharmacy - Downtown"
        }
    }
    
    # Run verification
    result = verify_set_preferred_pharmacy(
        traj={},
        env_info={"copy_from_env": mock_copy},
        task_info=task_info
    )
    
    print(f"\nVerification Result:")
    print(f"  Passed: {result['passed']}")
    print(f"  Score: {result['score']}/100")
    print(f"  Feedback: {result['feedback']}")
    if 'subscores' in result:
        print(f"  Subscores: {result['subscores']}")