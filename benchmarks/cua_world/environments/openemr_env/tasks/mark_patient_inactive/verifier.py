#!/usr/bin/env python3
"""
Verifier for Mark Patient Inactive task in OpenEMR

Verifies that:
1. The target patient (Maria Hickle) was found in the database
2. The patient's active status was changed from 1 (Active) to 0 (Inactive)
3. The correct patient was modified (not a different patient)
4. The change was made during the task execution

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mark_patient_inactive(traj, env_info, task_info):
    """
    Verify that the patient Maria Hickle was marked as inactive.

    Scoring (100 points total):
    - Patient found in database: 20 points
    - Status changed to inactive (0): 40 points
    - Correct patient was modified: 20 points
    - Change detected (status different from initial): 15 points
    - Screenshot evidence available: 5 points

    Passing threshold: 75 points with status_changed required
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
    expected_fname = metadata.get('patient_fname', 'Maria')
    expected_lname = metadata.get('patient_lname', 'Hickle')
    expected_initial_status = str(metadata.get('expected_initial_status', 1))
    expected_final_status = str(metadata.get('expected_final_status', 0))

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/mark_inactive_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "patient_found": False,
            "status_inactive": False,
            "correct_patient": False,
            "status_changed": False,
            "screenshot_exists": False
        }

        # Extract data from result
        patient_found = result.get('patient_found', False)
        patient_data = result.get('patient_data', {})
        verification = result.get('verification', {})
        target_patient = result.get('target_patient', {})

        logger.info(f"Result data: found={patient_found}, patient={patient_data}")
        logger.info(f"Verification: {verification}")

        # CRITERION 1: Patient found in database (20 points)
        if patient_found:
            score += 20
            subscores["patient_found"] = True
            db_fname = patient_data.get('fname', '')
            db_lname = patient_data.get('lname', '')
            feedback_parts.append(f"✅ Patient '{db_fname} {db_lname}' found in database")
        else:
            feedback_parts.append(f"❌ Patient '{expected_fname} {expected_lname}' NOT found in database")
            # Cannot proceed without patient
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Status is now inactive (40 points)
        current_status = str(patient_data.get('active', '1'))
        if current_status == '0':
            score += 40
            subscores["status_inactive"] = True
            feedback_parts.append("✅ Patient status is now Inactive (active=0)")
        else:
            feedback_parts.append(f"❌ Patient status is still Active (active={current_status})")

        # CRITERION 3: Correct patient was modified (20 points)
        correct_patient = verification.get('correct_patient_modified', False)
        expected_pid = target_patient.get('expected_pid', '')
        actual_pid = patient_data.get('pid', '')
        
        if correct_patient or (expected_pid and expected_pid == actual_pid):
            score += 20
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient modified (PID: {actual_pid})")
        elif expected_pid and expected_pid != actual_pid:
            feedback_parts.append(f"⚠️ PID mismatch: expected {expected_pid}, got {actual_pid}")
        else:
            # Give benefit of doubt if PIDs match by name
            db_fname = patient_data.get('fname', '').lower()
            db_lname = patient_data.get('lname', '').lower()
            if db_fname == expected_fname.lower() and db_lname == expected_lname.lower():
                score += 20
                subscores["correct_patient"] = True
                feedback_parts.append(f"✅ Correct patient (name match): {expected_fname} {expected_lname}")
            else:
                feedback_parts.append(f"⚠️ Could not verify correct patient was modified")

        # CRITERION 4: Status actually changed from initial (15 points)
        status_changed = verification.get('status_changed', False)
        initial_status = verification.get('initial_status', '1')
        
        if status_changed:
            score += 15
            subscores["status_changed"] = True
            feedback_parts.append(f"✅ Status changed: {initial_status} → {current_status}")
        elif current_status == '0' and initial_status == '1':
            # Calculate from raw values if flag not set
            score += 15
            subscores["status_changed"] = True
            feedback_parts.append(f"✅ Status changed: Active → Inactive")
        elif current_status == '0' and initial_status == '0':
            feedback_parts.append("⚠️ Patient was already inactive before task")
        else:
            feedback_parts.append(f"❌ Status did not change (still {current_status})")

        # CRITERION 5: Screenshot evidence (5 points)
        screenshot_path = result.get('screenshot_path', '')
        if screenshot_path:
            score += 5
            subscores["screenshot_exists"] = True
            feedback_parts.append("✅ Final screenshot captured")

        # Determine pass/fail
        # Must have: patient found + status is inactive + (status changed OR correct patient)
        key_criteria_met = (
            subscores["patient_found"] and 
            subscores["status_inactive"] and
            (subscores["status_changed"] or subscores["correct_patient"])
        )
        
        passed = score >= 75 and key_criteria_met

        # VLM verification for additional confidence (optional)
        vlm_feedback = ""
        try:
            query_vlm = env_info.get('query_vlm')
            if query_vlm and traj:
                # Import trajectory utilities
                try:
                    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                    
                    # Sample frames from trajectory to verify work was done
                    frames = sample_trajectory_frames(traj, n=4)
                    final_screenshot = get_final_screenshot(traj)
                    
                    if frames or final_screenshot:
                        all_images = frames + ([final_screenshot] if final_screenshot else [])
                        
                        vlm_prompt = """Analyze these screenshots from an OpenEMR task.
                        
The task was to mark patient Maria Hickle as inactive by:
1. Logging into OpenEMR
2. Finding the patient
3. Opening Demographics/Edit
4. Changing the Active status
5. Saving

Look at the screenshots and determine:
- Did the agent navigate to patient demographics?
- Did the agent access the edit/demographics form?
- Is there evidence of changing a checkbox or status field?
- Was there a save/update action?

Respond with JSON:
{
    "demographics_accessed": true/false,
    "edit_form_visible": true/false,
    "status_change_attempted": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
                        
                        vlm_result = query_vlm(
                            prompt=vlm_prompt,
                            images=all_images
                        )
                        
                        if vlm_result.get('success'):
                            parsed = vlm_result.get('parsed', {})
                            if parsed.get('status_change_attempted') and parsed.get('confidence') in ['medium', 'high']:
                                vlm_feedback = " | VLM confirms status change workflow"
                            elif parsed.get('demographics_accessed'):
                                vlm_feedback = " | VLM confirms demographics accessed"
                                
                except ImportError:
                    logger.debug("VLM utilities not available")
        except Exception as e:
            logger.debug(f"VLM verification skipped: {e}")

        feedback = " | ".join(feedback_parts) + vlm_feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_fname": patient_data.get('fname', ''),
                "patient_lname": patient_data.get('lname', ''),
                "patient_pid": patient_data.get('pid', ''),
                "initial_status": initial_status,
                "final_status": current_status,
                "status_changed": subscores["status_changed"]
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
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }