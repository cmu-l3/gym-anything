#!/usr/bin/env python3
"""
Verifier for Update Emergency Contact task in OpenEMR

Verifies that the agent successfully updated a patient's emergency contact information
by checking database values and applying anti-gaming measures.

Scoring (100 points total):
- Correct patient selected: 15 points
- Demographics section accessed (via trajectory): 15 points
- Emergency contact name updated correctly: 25 points
- Emergency phone updated correctly: 25 points
- Changes persisted to database: 10 points
- Record modified during task (anti-gaming): 10 points

Pass threshold: 70 points
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_phone(phone_str):
    """Extract digits from phone number for comparison."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', str(phone_str))


def normalize_name(name_str):
    """Normalize name for comparison (lowercase, strip whitespace)."""
    if not name_str:
        return ""
    return str(name_str).lower().strip()


def verify_update_emergency_contact(traj, env_info, task_info):
    """
    Verify that emergency contact information was correctly updated.
    
    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info containing copy_from_env function
        task_info: Task metadata with expected values
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 2)
    expected_fname = metadata.get('patient_fname', 'Frances')
    expected_lname = metadata.get('patient_lname', 'Will')
    expected_em_contact = metadata.get('expected_em_contact', 'Robert Will')
    expected_em_phone = metadata.get('expected_em_phone', '6175559876')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/emergency_contact_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "demographics_accessed": False,
            "contact_name_correct": False,
            "phone_correct": False,
            "changes_persisted": False,
            "modified_during_task": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        patient_name = result.get('patient_name', '')
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)
        
        initial_values = result.get('initial_values', {})
        current_values = result.get('current_values', {})
        changes = result.get('changes', {})
        validation = result.get('validation', {})
        
        record_modified_ts = result.get('record_modified_timestamp', 0)

        logger.info(f"Verifying update for patient pid={patient_pid}, name={patient_name}")
        logger.info(f"Initial: {initial_values}")
        logger.info(f"Current: {current_values}")
        logger.info(f"Changes: {changes}")

        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient selected (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Wrong patient is a critical failure
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient selected. Expected Frances Will (pid=2), but changes were for pid={patient_pid}",
                "subscores": subscores
            }

        # CRITERION 2: Demographics section accessed - check via trajectory (15 points)
        # Use VLM to verify the agent navigated to demographics
        demographics_accessed = False
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            try:
                # Import trajectory sampling utility
                from gym_anything.vlm import sample_trajectory_frames
                
                # Sample frames from trajectory to see if demographics was accessed
                frames = sample_trajectory_frames(traj, n=5)
                
                if frames:
                    vlm_prompt = """Analyze these screenshots from an OpenEMR session. 
                    
Did the user navigate to and interact with a patient's Demographics page?

Look for evidence of:
1. Patient demographics screen or edit form
2. Emergency contact fields visible or being edited
3. Contact information entry fields
4. Patient information editing interface

Respond in JSON format:
{
    "demographics_page_visible": true/false,
    "emergency_contact_fields_visible": true/false,
    "editing_occurred": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
                    
                    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('demographics_page_visible') or parsed.get('emergency_contact_fields_visible'):
                            demographics_accessed = True
                            logger.info(f"VLM confirmed demographics access: {parsed}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                # Fall back to assuming access if values changed
                if changes.get('contact_changed') or changes.get('phone_changed'):
                    demographics_accessed = True

        # If VLM not available, infer from data changes
        if not demographics_accessed and (changes.get('contact_changed') or changes.get('phone_changed')):
            demographics_accessed = True

        if demographics_accessed:
            score += 15
            subscores["demographics_accessed"] = True
            feedback_parts.append("✅ Demographics section was accessed")
        else:
            feedback_parts.append("⚠️ Could not confirm demographics section access")

        # CRITERION 3: Emergency contact name updated correctly (25 points)
        current_em_contact = current_values.get('em_contact', '')
        initial_em_contact = initial_values.get('em_contact', '')
        
        current_contact_normalized = normalize_name(current_em_contact)
        expected_contact_normalized = normalize_name(expected_em_contact)
        
        # Check if contact name matches expected value
        contact_name_correct = False
        if current_contact_normalized == expected_contact_normalized:
            contact_name_correct = True
        elif 'robert' in current_contact_normalized and 'will' in current_contact_normalized:
            # Partial match - name contains expected first and last name
            contact_name_correct = True
        
        if contact_name_correct:
            score += 25
            subscores["contact_name_correct"] = True
            feedback_parts.append(f"✅ Emergency contact name correct: '{current_em_contact}'")
        elif changes.get('contact_changed'):
            # Contact was changed but not to expected value
            score += 10  # Partial credit for making a change
            feedback_parts.append(f"⚠️ Contact changed but incorrect: expected '{expected_em_contact}', got '{current_em_contact}'")
        else:
            feedback_parts.append(f"❌ Emergency contact name not updated (still '{current_em_contact}')")

        # CRITERION 4: Emergency phone updated correctly (25 points)
        current_em_phone = current_values.get('em_phone', '')
        current_phone_digits = current_values.get('em_phone_digits', normalize_phone(current_em_phone))
        initial_em_phone = initial_values.get('em_phone', '')
        
        phone_correct = False
        if current_phone_digits == expected_em_phone:
            phone_correct = True
        elif expected_em_phone in current_phone_digits:
            phone_correct = True
        
        if phone_correct:
            score += 25
            subscores["phone_correct"] = True
            feedback_parts.append(f"✅ Emergency phone correct: '{current_em_phone}'")
        elif changes.get('phone_changed'):
            # Phone was changed but not to expected value
            score += 10  # Partial credit
            feedback_parts.append(f"⚠️ Phone changed but incorrect: expected '(617) 555-9876', got '{current_em_phone}'")
        else:
            feedback_parts.append(f"❌ Emergency phone not updated (still '{current_em_phone}')")

        # CRITERION 5: Changes persisted to database (10 points)
        if validation.get('contact_correct') or validation.get('phone_correct'):
            score += 10
            subscores["changes_persisted"] = True
            feedback_parts.append("✅ Changes persisted to database")
        elif changes.get('contact_changed') or changes.get('phone_changed'):
            score += 5  # Partial credit - something changed
            feedback_parts.append("⚠️ Some changes detected in database")
        else:
            feedback_parts.append("❌ No changes detected in database")

        # CRITERION 6: Record modified during task - anti-gaming (10 points)
        if changes.get('record_modified_during_task'):
            score += 10
            subscores["modified_during_task"] = True
            feedback_parts.append("✅ Record modification timestamp updated during task")
        elif task_start > 0 and record_modified_ts > task_start:
            score += 10
            subscores["modified_during_task"] = True
            feedback_parts.append("✅ Record was modified after task started")
        else:
            # Check if values actually changed as fallback
            if current_em_contact != initial_em_contact or current_em_phone != initial_em_phone:
                score += 5  # Partial credit
                feedback_parts.append("⚠️ Values changed but modification timestamp not updated")
            else:
                feedback_parts.append("❌ No evidence of record modification during task (possible pre-existing data)")

        # Determine pass/fail
        # Must have correct patient AND at least one field correct
        key_criteria_met = (
            subscores["correct_patient"] and 
            (subscores["contact_name_correct"] or subscores["phone_correct"])
        )
        passed = score >= 70 and key_criteria_met

        # Generate summary feedback
        if passed:
            feedback_summary = f"✅ PASSED (Score: {score}/100) - Emergency contact successfully updated"
        elif score >= 50:
            feedback_summary = f"⚠️ PARTIAL (Score: {score}/100) - Some updates made but incomplete"
        else:
            feedback_summary = f"❌ FAILED (Score: {score}/100) - Emergency contact not properly updated"

        feedback = feedback_summary + "\n\nDetails:\n- " + "\n- ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "expected": {
                    "contact_name": expected_em_contact,
                    "phone": expected_em_phone
                },
                "actual": {
                    "contact_name": current_em_contact,
                    "phone": current_em_phone
                },
                "changed_from": {
                    "contact_name": initial_em_contact,
                    "phone": initial_em_phone
                }
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - export_result.sh may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {}
        }