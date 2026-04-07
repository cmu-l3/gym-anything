#!/usr/bin/env python3
"""
Verifier for Record Patient SOGI (Sexual Orientation and Gender Identity) Task

Verification Strategy:
1. PRIMARY: Database query to verify SOGI fields were populated correctly
2. SECONDARY: Check record modification timestamp to detect gaming
3. TERTIARY: VLM verification on trajectory to confirm workflow was followed

Scoring (100 points total):
- Sexual Orientation recorded correctly: 35 points
- Gender Identity recorded correctly: 35 points  
- Correct patient modified (pid=6): 15 points
- Record timestamp updated during task: 10 points
- No data corruption (other fields unchanged): 5 points
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_record_patient_sogi(traj, env_info, task_info):
    """
    Verify that SOGI data was correctly recorded for patient Truman Crooks.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 6)
    expected_so = metadata.get('expected_sexual_orientation', 'bisexual').lower()
    expected_gi = metadata.get('expected_gender_identity', 'male').lower()
    expected_sex = metadata.get('expected_sex', 'Male').lower()
    
    scoring_weights = metadata.get('scoring_weights', {
        'sexual_orientation_correct': 35,
        'gender_identity_correct': 35,
        'correct_patient_modified': 15,
        'record_timestamp_updated': 10,
        'no_data_corruption': 5
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/sogi_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "sexual_orientation_correct": False,
            "gender_identity_correct": False,
            "correct_patient_modified": False,
            "record_timestamp_updated": False,
            "no_data_corruption": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start_timestamp', 0)
        current_modified = result.get('current_modified_timestamp', 0)
        record_modified = result.get('record_modified_during_task', False)
        sogi_changed = result.get('sogi_values_changed', False)
        current_values = result.get('current_values', {})
        validation = result.get('validation', {})

        actual_so = current_values.get('sexual_orientation', '').lower().strip()
        actual_gi = current_values.get('gender_identity', '').lower().strip()
        actual_sex = current_values.get('sex', '').lower().strip()

        logger.info(f"Patient PID: {patient_pid}")
        logger.info(f"Current values - SO: '{actual_so}', GI: '{actual_gi}', Sex: '{actual_sex}'")
        logger.info(f"Record modified during task: {record_modified}")

        # CRITERION 1: Correct patient modified (15 points)
        if patient_pid == expected_pid:
            score += scoring_weights.get('correct_patient_modified', 15)
            subscores["correct_patient_modified"] = True
            feedback_parts.append(f"✅ Correct patient modified (pid={expected_pid})")
        else:
            feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient modified (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: Sexual Orientation correct (35 points)
        so_match = check_sexual_orientation_match(actual_so, expected_so)
        if so_match:
            score += scoring_weights.get('sexual_orientation_correct', 35)
            subscores["sexual_orientation_correct"] = True
            feedback_parts.append(f"✅ Sexual Orientation correctly set to '{actual_so}'")
        else:
            if actual_so:
                feedback_parts.append(f"❌ Sexual Orientation incorrect: expected '{expected_so}', got '{actual_so}'")
            else:
                feedback_parts.append(f"❌ Sexual Orientation not set (expected '{expected_so}')")

        # CRITERION 3: Gender Identity correct (35 points)
        gi_match = check_gender_identity_match(actual_gi, expected_gi)
        if gi_match:
            score += scoring_weights.get('gender_identity_correct', 35)
            subscores["gender_identity_correct"] = True
            feedback_parts.append(f"✅ Gender Identity correctly set to '{actual_gi}'")
        else:
            if actual_gi:
                feedback_parts.append(f"❌ Gender Identity incorrect: expected '{expected_gi}', got '{actual_gi}'")
            else:
                feedback_parts.append(f"❌ Gender Identity not set (expected '{expected_gi}')")

        # CRITERION 4: Record timestamp updated (10 points) - anti-gaming check
        if record_modified or sogi_changed:
            score += scoring_weights.get('record_timestamp_updated', 10)
            subscores["record_timestamp_updated"] = True
            feedback_parts.append("✅ Record was modified during task (anti-gaming check passed)")
        else:
            # Check if values might have been pre-set (gaming attempt)
            if so_match and gi_match:
                feedback_parts.append("⚠️ Values correct but record may not have been modified during task")
            else:
                feedback_parts.append("❌ Record not modified during task")

        # CRITERION 5: No data corruption (5 points)
        # Check that sex field is still valid
        sex_valid = actual_sex in ['male', 'm', 'female', 'f']
        if sex_valid:
            score += scoring_weights.get('no_data_corruption', 5)
            subscores["no_data_corruption"] = True
            feedback_parts.append("✅ No data corruption detected")
        else:
            feedback_parts.append(f"⚠️ Sex field may have invalid value: '{actual_sex}'")

        # VLM verification for additional confidence (optional bonus)
        vlm_score = 0
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            try:
                vlm_result = verify_via_vlm(traj, query_vlm)
                if vlm_result.get('workflow_confirmed', False):
                    feedback_parts.append("✅ VLM confirmed demographics editing workflow")
                    # VLM is supplementary, not scored separately
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        # Calculate pass/fail
        # Must have at least one SOGI field correct and correct patient
        key_criteria_met = (
            subscores["correct_patient_modified"] and 
            (subscores["sexual_orientation_correct"] or subscores["gender_identity_correct"])
        )
        
        passed = score >= 70 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "actual_sexual_orientation": actual_so,
                "actual_gender_identity": actual_gi,
                "actual_sex": actual_sex,
                "record_modified": record_modified,
                "sogi_changed": sogi_changed
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        logger.exception("Verification failed with exception")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def check_sexual_orientation_match(actual: str, expected: str) -> bool:
    """
    Check if the actual sexual orientation value matches expected.
    Handles various representations of 'bisexual'.
    
    Args:
        actual: Actual value from database (lowercase)
        expected: Expected value (lowercase)
        
    Returns:
        bool: True if values match
    """
    if not actual:
        return False
        
    actual = actual.lower().strip()
    expected = expected.lower().strip()
    
    # Direct match
    if expected in actual or actual in expected:
        return True
    
    # Bisexual variants
    bisexual_patterns = [
        'bisexual', 'bi', 'bi-sexual', 'bisex'
    ]
    
    if expected == 'bisexual':
        for pattern in bisexual_patterns:
            if pattern in actual:
                return True
    
    return False


def check_gender_identity_match(actual: str, expected: str) -> bool:
    """
    Check if the actual gender identity value matches expected.
    Handles various representations of 'identifies as male'.
    
    Args:
        actual: Actual value from database (lowercase)
        expected: Expected value (lowercase)
        
    Returns:
        bool: True if values match
    """
    if not actual:
        return False
        
    actual = actual.lower().strip()
    expected = expected.lower().strip()
    
    # Direct match
    if expected in actual or actual in expected:
        return True
    
    # Male identity variants
    male_patterns = [
        'male', 'identifies as male', 'identifies_as_male',
        'man', 'cisgender male', 'cis male', 'cis-male'
    ]
    
    if expected == 'male':
        for pattern in male_patterns:
            if pattern in actual or actual == pattern:
                return True
        # Also check if it's just 'male' code
        if actual == 'm':
            return True
    
    return False


def verify_via_vlm(traj, query_vlm) -> dict:
    """
    Use VLM to verify the workflow was followed correctly.
    Checks trajectory frames for demographics editing workflow.
    
    Args:
        traj: Trajectory data
        query_vlm: VLM query function
        
    Returns:
        dict with verification results
    """
    try:
        # Import trajectory utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if not frames and not final_frame:
            return {"workflow_confirmed": False, "error": "No frames available"}
        
        # Use final frame if trajectory frames unavailable
        images = frames + [final_frame] if final_frame else frames
        
        vlm_prompt = """Analyze these screenshots from an OpenEMR session.
        
Task: Record Sexual Orientation and Gender Identity (SOGI) data for a patient.

Verify if the following workflow steps are visible in ANY of the screenshots:
1. Patient search or patient chart opened
2. Demographics section accessed (editing mode)
3. SOGI fields visible (Sexual Orientation, Gender Identity dropdowns)
4. Form appears to be saved/submitted

Look for:
- Patient name "Truman Crooks" visible
- Demographics edit form or patient information page
- Dropdown fields for Sexual Orientation and/or Gender Identity
- Save/Update button clicked or confirmation message

Respond in JSON format:
{
    "patient_chart_visible": true/false,
    "demographics_editing": true/false,
    "sogi_fields_visible": true/false,
    "form_saved": true/false,
    "workflow_confirmed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""

        result = query_vlm(prompt=vlm_prompt, images=images)
        
        if result.get('success'):
            parsed = result.get('parsed', {})
            return {
                "workflow_confirmed": parsed.get('workflow_confirmed', False),
                "demographics_editing": parsed.get('demographics_editing', False),
                "sogi_fields_visible": parsed.get('sogi_fields_visible', False),
                "confidence": parsed.get('confidence', 'low'),
                "reasoning": parsed.get('reasoning', '')
            }
        else:
            return {"workflow_confirmed": False, "error": result.get('error', 'VLM query failed')}
            
    except ImportError:
        logger.warning("VLM utilities not available")
        return {"workflow_confirmed": False, "error": "VLM utilities not available"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"workflow_confirmed": False, "error": str(e)}


if __name__ == "__main__":
    # Test mode - run verification with mock data
    print("SOGI Task Verifier - Test Mode")
    
    # Mock result for testing
    mock_result = {
        "patient_pid": 6,
        "task_start_timestamp": 1700000000,
        "current_modified_timestamp": 1700000100,
        "record_modified_during_task": True,
        "sogi_values_changed": True,
        "current_values": {
            "sexual_orientation": "bisexual",
            "gender_identity": "male",
            "sex": "Male"
        },
        "validation": {
            "sexual_orientation_valid": True,
            "gender_identity_valid": True,
            "sex_valid": True
        }
    }
    
    print(f"Mock result: {json.dumps(mock_result, indent=2)}")
    print("\nExpected: PASS with score ~100")