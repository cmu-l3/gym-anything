#!/usr/bin/env python3
"""
Verifier for Add Encounter Diagnosis task in OpenEMR

This task verifies that an ICD-10 diagnosis code for COPD (J44.x) was added
to a patient encounter. It uses copy_from_env to read pre-exported verification
data from the container.

Scoring (100 points total):
- Patient located correctly: 15 points
- Encounter accessed: 20 points
- Diagnosis section used (any ICD10 code activity): 15 points
- Correct ICD-10 code added (J44.x): 30 points
- Code linked to encounter: 15 points
- Code saved as active: 5 points

Pass threshold: 70 points with ICD-10 code added criterion met
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_encounter_diagnosis(traj, env_info, task_info):
    """
    Verify that an ICD-10 diagnosis code was correctly added to a patient encounter.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata including expected values
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available for verification"
        }
    
    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 2)
    expected_fname = metadata.get('patient_fname', 'Rozella')
    expected_lname = metadata.get('patient_lname', 'Corkery')
    valid_codes = metadata.get('valid_icd10_codes', ['J44.1', 'J44.9', 'J44.0', 'J44'])
    scoring_weights = metadata.get('scoring_weights', {
        'patient_located': 15,
        'encounter_accessed': 20,
        'diagnosis_section_used': 15,
        'icd10_code_added': 30,
        'code_linked_encounter': 15,
        'code_saved_active': 5
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/encounter_diagnosis_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "patient_located": False,
            "encounter_accessed": False,
            "diagnosis_section_used": False,
            "icd10_code_added": False,
            "code_linked_to_encounter": False,
            "code_saved_active": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_dx_count = result.get('initial_dx_count', 0)
        current_dx_count = result.get('current_dx_count', 0)
        initial_copd_count = result.get('initial_copd_count', 0)
        current_copd_count = result.get('current_copd_count', 0)
        copd_code_found = result.get('copd_code_found', False)
        new_code_added = result.get('new_code_added', False)
        diagnosis = result.get('diagnosis', {})
        validation = result.get('validation', {})
        
        logger.info(f"Patient PID: {patient_pid}, Expected: {expected_pid}")
        logger.info(f"Initial DX count: {initial_dx_count}, Current: {current_dx_count}")
        logger.info(f"Initial COPD count: {initial_copd_count}, Current: {current_copd_count}")
        logger.info(f"COPD code found: {copd_code_found}")
        logger.info(f"Diagnosis data: {diagnosis}")
        
        # CRITERION 1: Patient located correctly (15 points)
        if patient_pid == expected_pid:
            score += scoring_weights.get('patient_located', 15)
            subscores["patient_located"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient - expected pid={expected_pid}, got {patient_pid}")
            # If wrong patient, fail immediately - this is a critical error
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient targeted. Expected pid={expected_pid} ({expected_fname} {expected_lname})",
                "subscores": subscores
            }
        
        # CRITERION 2: Encounter accessed (20 points)
        # We infer this if diagnosis activity was detected
        target_encounter = result.get('target_encounter', '')
        diagnosis_encounter = diagnosis.get('encounter', '')
        if diagnosis_encounter and diagnosis_encounter != '0':
            score += scoring_weights.get('encounter_accessed', 20)
            subscores["encounter_accessed"] = True
            feedback_parts.append(f"✅ Encounter accessed (encounter={diagnosis_encounter})")
        elif current_dx_count > initial_dx_count:
            # Some diagnosis activity happened
            score += scoring_weights.get('encounter_accessed', 20) // 2
            feedback_parts.append("⚠️ Diagnosis activity detected but encounter linkage unclear")
        else:
            feedback_parts.append("❌ No encounter accessed or diagnosis activity detected")
        
        # CRITERION 3: Diagnosis section used (15 points)
        # Any increase in ICD10 codes indicates the section was used
        if current_dx_count > initial_dx_count:
            score += scoring_weights.get('diagnosis_section_used', 15)
            subscores["diagnosis_section_used"] = True
            feedback_parts.append(f"✅ Diagnosis section used (ICD10 count: {initial_dx_count} → {current_dx_count})")
        elif copd_code_found and new_code_added:
            score += scoring_weights.get('diagnosis_section_used', 15)
            subscores["diagnosis_section_used"] = True
            feedback_parts.append("✅ Diagnosis section used (COPD code added)")
        else:
            feedback_parts.append("❌ No new ICD10 codes added during task")
        
        # CRITERION 4: Correct ICD-10 code added (30 points) - CRITICAL
        diagnosis_code = diagnosis.get('code', '')
        code_is_valid = False
        
        if diagnosis_code:
            # Check if it's a valid COPD code
            for valid_code in valid_codes:
                if diagnosis_code.upper().startswith(valid_code.upper()):
                    code_is_valid = True
                    break
            
            # Also accept any J44.x pattern
            if diagnosis_code.upper().startswith('J44'):
                code_is_valid = True
        
        if copd_code_found and code_is_valid and new_code_added:
            score += scoring_weights.get('icd10_code_added', 30)
            subscores["icd10_code_added"] = True
            feedback_parts.append(f"✅ Correct ICD-10 code added: {diagnosis_code}")
        elif copd_code_found and code_is_valid:
            # Code exists but might be pre-existing - partial credit
            score += scoring_weights.get('icd10_code_added', 30) // 2
            feedback_parts.append(f"⚠️ Valid COPD code {diagnosis_code} found but may not be new")
        elif diagnosis_code:
            feedback_parts.append(f"❌ Code {diagnosis_code} added but not a valid COPD code (expected J44.x)")
        else:
            feedback_parts.append("❌ No COPD diagnosis code (J44.x) added")
        
        # CRITERION 5: Code linked to encounter (15 points)
        code_linked = validation.get('code_linked_to_encounter', False)
        if code_linked:
            score += scoring_weights.get('code_linked_encounter', 15)
            subscores["code_linked_to_encounter"] = True
            feedback_parts.append(f"✅ Code properly linked to encounter {diagnosis_encounter}")
        elif diagnosis_encounter and diagnosis_encounter != '0':
            # Has encounter field but we couldn't verify linkage
            score += scoring_weights.get('code_linked_encounter', 15) // 2
            feedback_parts.append(f"⚠️ Code has encounter reference ({diagnosis_encounter}) but linkage unverified")
        else:
            feedback_parts.append("❌ Code not linked to an encounter")
        
        # CRITERION 6: Code saved as active (5 points)
        code_active = diagnosis.get('active', '0')
        if code_active == '1' or code_active == 1 or code_active == True:
            score += scoring_weights.get('code_saved_active', 5)
            subscores["code_saved_active"] = True
            feedback_parts.append("✅ Code saved with active status")
        elif copd_code_found:
            feedback_parts.append(f"⚠️ Code found but active status is: {code_active}")
        else:
            feedback_parts.append("❌ Code not saved or not active")
        
        # Determine pass/fail
        # Must have: correct patient + ICD10 code added
        key_criteria_met = (
            subscores["patient_located"] and 
            subscores["icd10_code_added"]
        )
        passed = score >= 70 and key_criteria_met
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score}/100, Passed: {passed}")
        logger.info(f"Subscores: {subscores}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "diagnosis_code": diagnosis_code,
                "encounter": diagnosis_encounter,
                "new_code_added": new_code_added,
                "initial_copd_count": initial_copd_count,
                "current_copd_count": current_copd_count
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found in container")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification data not found. Export script may have failed.",
            "subscores": {
                "patient_located": False,
                "encounter_accessed": False,
                "diagnosis_section_used": False,
                "icd10_code_added": False,
                "code_linked_to_encounter": False,
                "code_saved_active": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse verification data: {e}",
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
    # Mock test with sample data
    import tempfile
    import json
    
    # Create mock result data
    mock_result = {
        "patient_pid": 2,
        "target_encounter": "5",
        "task_start_time": 1700000000,
        "task_end_time": 1700000300,
        "initial_dx_count": 0,
        "current_dx_count": 1,
        "initial_copd_count": 0,
        "current_copd_count": 1,
        "copd_code_found": True,
        "new_code_added": True,
        "diagnosis": {
            "id": "1",
            "encounter": "5",
            "code": "J44.9",
            "code_text": "Chronic obstructive pulmonary disease, unspecified",
            "active": "1"
        },
        "validation": {
            "code_linked_to_encounter": True,
            "code_value_valid": True,
            "new_code_added": True
        }
    }
    
    # Create temporary file
    temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(mock_result, temp_file)
    temp_file.close()
    
    # Mock copy_from_env
    def mock_copy_from_env(src, dst):
        import shutil
        shutil.copy(temp_file.name, dst)
    
    # Test verification
    result = verify_encounter_diagnosis(
        traj={},
        env_info={'copy_from_env': mock_copy_from_env},
        task_info={'metadata': {'patient_pid': 2, 'patient_fname': 'Rozella', 'patient_lname': 'Corkery'}}
    )
    
    print(f"\nTest Result:")
    print(f"  Passed: {result['passed']}")
    print(f"  Score: {result['score']}/100")
    print(f"  Feedback: {result['feedback']}")
    print(f"  Subscores: {result.get('subscores', {})}")
    
    # Cleanup
    os.unlink(temp_file.name)