#!/usr/bin/env python3
"""
Verifier for Set Communication Preference task in OpenEMR

Verifies that the agent correctly updated patient communication preferences:
1. Patient Sofia Bradtke (pid=5) was found
2. Demographics were edited
3. hipaa_allowemail was set to YES
4. hipaa_voice was set to NO
5. Changes were saved (record modified)

Uses copy_from_env to read exported JSON data.
Uses VLM trajectory verification as secondary check.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_communication_preference(traj, env_info, task_info):
    """
    Verify that communication preferences were correctly updated for patient.
    
    Scoring (100 points total):
    - Logged in successfully: 10 points (VLM check)
    - Found correct patient: 15 points
    - Accessed demographics edit: 15 points (VLM check)
    - Email preference set to YES: 20 points
    - Voice preference set to NO: 25 points
    - Changes saved (record modified): 15 points
    
    Pass threshold: 70 points with at least one preference correctly updated
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
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Sofia')
    expected_lname = metadata.get('patient_lname', 'Bradtke')
    expected_email_pref = metadata.get('expected_hipaa_allowemail', 'YES')
    expected_voice_pref = metadata.get('expected_hipaa_voice', 'NO')
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/comm_pref_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "logged_in": False,
            "found_patient": False,
            "accessed_edit": False,
            "email_correct": False,
            "voice_correct": False,
            "changes_saved": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        patient_fname = result.get('patient_fname', '')
        patient_lname = result.get('patient_lname', '')
        
        initial_values = result.get('initial_values', {})
        current_values = result.get('current_values', {})
        validation = result.get('validation', {})
        
        logger.info(f"Patient: {patient_fname} {patient_lname} (pid={patient_pid})")
        logger.info(f"Initial values: {initial_values}")
        logger.info(f"Current values: {current_values}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Found correct patient (15 points)
        if patient_pid == expected_pid:
            if patient_fname.lower() == expected_fname.lower() and patient_lname.lower() == expected_lname.lower():
                score += 15
                subscores["found_patient"] = True
                feedback_parts.append(f"✅ Correct patient found: {patient_fname} {patient_lname} (pid={patient_pid})")
            else:
                feedback_parts.append(f"⚠️ Patient pid matches but name differs: {patient_fname} {patient_lname}")
                score += 10  # Partial credit
        else:
            feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient selected (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        # CRITERION 2: Email preference set to YES (20 points)
        current_email = current_values.get('hipaa_allowemail', '').upper()
        initial_email = initial_values.get('hipaa_allowemail', '').upper()
        
        if current_email == expected_email_pref.upper():
            score += 20
            subscores["email_correct"] = True
            if current_email != initial_email:
                feedback_parts.append(f"✅ Email preference correctly updated: {initial_email} → {current_email}")
            else:
                feedback_parts.append(f"✅ Email preference correct: {current_email} (was already set)")
        else:
            feedback_parts.append(f"❌ Email preference incorrect: expected {expected_email_pref}, got '{current_email}'")
        
        # CRITERION 3: Voice preference set to NO (25 points)
        current_voice = current_values.get('hipaa_voice', '').upper()
        initial_voice = initial_values.get('hipaa_voice', '').upper()
        
        if current_voice == expected_voice_pref.upper():
            score += 25
            subscores["voice_correct"] = True
            if current_voice != initial_voice:
                feedback_parts.append(f"✅ Voice preference correctly updated: {initial_voice} → {current_voice}")
            else:
                feedback_parts.append(f"✅ Voice preference correct: {current_voice} (was already set)")
        else:
            feedback_parts.append(f"❌ Voice preference incorrect: expected {expected_voice_pref}, got '{current_voice}'")
        
        # CRITERION 4: Changes were saved (15 points)
        record_modified = validation.get('record_modified', False)
        email_changed = validation.get('email_preference_changed', False)
        voice_changed = validation.get('voice_preference_changed', False)
        
        if record_modified or email_changed or voice_changed:
            score += 15
            subscores["changes_saved"] = True
            feedback_parts.append("✅ Changes were saved to database")
        else:
            # Check if preferences were already correct (no change needed)
            if subscores["email_correct"] and subscores["voice_correct"]:
                score += 10  # Partial credit if already correct
                subscores["changes_saved"] = True
                feedback_parts.append("⚠️ Preferences correct but no change detected (may have been pre-set)")
            else:
                feedback_parts.append("❌ No changes detected in database")
        
        # VLM Verification for workflow steps (logged in, accessed edit)
        vlm_score = _verify_workflow_via_vlm(traj, env_info, subscores, feedback_parts)
        score += vlm_score
        
        # Calculate pass/fail
        # Must have at least one preference correct and changes saved
        key_criteria_met = (subscores["email_correct"] or subscores["voice_correct"]) and \
                          (subscores["changes_saved"] or record_modified)
        passed = score >= 70 and key_criteria_met
        
        # Add summary
        feedback_parts.append(f"\nTotal Score: {score}/100")
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "initial_values": initial_values,
                "current_values": current_values,
                "validation": validation
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
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


def _verify_workflow_via_vlm(traj, env_info, subscores, feedback_parts):
    """
    Use VLM to verify workflow steps from trajectory screenshots.
    
    Checks:
    - Agent logged in (10 points)
    - Agent accessed demographics edit mode (15 points)
    
    Returns additional score points.
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        # Give benefit of doubt if VLM not available but database checks passed
        if subscores.get("email_correct") or subscores.get("voice_correct"):
            subscores["logged_in"] = True
            subscores["accessed_edit"] = True
            return 25  # Full VLM points
        return 0
    
    vlm_score = 0
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        if not frames and not final_screenshot:
            logger.warning("No screenshots available for VLM verification")
            # Still give partial credit if database shows success
            if subscores.get("email_correct") or subscores.get("voice_correct"):
                return 15
            return 0
        
        all_frames = frames + ([final_screenshot] if final_screenshot else [])
        
        # VLM prompt to verify workflow
        vlm_prompt = """Analyze these screenshots from an OpenEMR session and determine:

1. Did the user successfully log in to OpenEMR? (Look for: dashboard, patient menu, logged-in username)
2. Did the user access patient demographics edit mode? (Look for: edit form, demographics fields, HIPAA/communication preferences section)
3. Did the user navigate to a patient record? (Look for: patient name "Sofia Bradtke" or patient details)

Respond in JSON format:
{
    "logged_in": true/false,
    "accessed_demographics": true/false,
    "patient_visible": true/false,
    "edit_mode_visible": true/false,
    "hipaa_section_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            # Check login (10 points)
            if parsed.get("logged_in", False):
                vlm_score += 10
                subscores["logged_in"] = True
                feedback_parts.append("✅ Login verified via screenshots")
            else:
                feedback_parts.append("⚠️ Login not clearly visible in screenshots")
            
            # Check demographics edit access (15 points)
            accessed_edit = parsed.get("accessed_demographics", False) or \
                           parsed.get("edit_mode_visible", False) or \
                           parsed.get("hipaa_section_visible", False)
            
            if accessed_edit:
                vlm_score += 15
                subscores["accessed_edit"] = True
                feedback_parts.append("✅ Demographics edit mode verified via screenshots")
            elif parsed.get("patient_visible", False):
                # Partial credit if patient was at least visible
                vlm_score += 8
                feedback_parts.append("⚠️ Patient visible but edit mode not confirmed")
            else:
                feedback_parts.append("⚠️ Demographics edit not clearly visible")
            
            logger.info(f"VLM verification result: {parsed}")
        else:
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            # Give partial credit if database shows success
            if subscores.get("email_correct") or subscores.get("voice_correct"):
                vlm_score = 15
                subscores["logged_in"] = True
                feedback_parts.append("⚠️ VLM check inconclusive, but database shows changes")
                
    except ImportError:
        logger.warning("VLM utilities not available")
        # Fallback: if database shows changes, assume workflow was correct
        if subscores.get("email_correct") or subscores.get("voice_correct"):
            vlm_score = 20
            subscores["logged_in"] = True
            subscores["accessed_edit"] = True
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Give partial credit on error if database checks passed
        if subscores.get("email_correct") or subscores.get("voice_correct"):
            vlm_score = 10
    
    return vlm_score


# Anti-gaming check: Ensure this wasn't a "do nothing" scenario
def _check_do_nothing(result):
    """
    Verify the agent actually did work, not just submitted.
    
    Returns True if suspicious (possible gaming), False if legitimate.
    """
    validation = result.get('validation', {})
    
    # If record wasn't modified and preferences didn't change, suspicious
    if not validation.get('record_modified', False) and \
       not validation.get('email_preference_changed', False) and \
       not validation.get('voice_preference_changed', False):
        
        # Check if values were already correct (legitimate case)
        current = result.get('current_values', {})
        if current.get('hipaa_allowemail', '').upper() == 'YES' and \
           current.get('hipaa_voice', '').upper() == 'NO':
            # Values correct but no change - could be pre-set, not gaming
            return False
        
        # No changes and values wrong - likely did nothing
        return True
    
    return False