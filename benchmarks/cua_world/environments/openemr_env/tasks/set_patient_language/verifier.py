#!/usr/bin/env python3
"""
Verifier for Set Patient Language task in OpenEMR

Verifies that the patient's preferred language was correctly set to Spanish.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.

Scoring (100 points total):
- Patient demographics accessed (correct patient): 15 points
- Language field was updated (changed from initial): 25 points  
- Language is set to Spanish variant: 35 points
- Change persisted to database: 15 points
- VLM trajectory verification: 10 points

Pass threshold: 75 points with language set to Spanish
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_spanish_language(value: str) -> bool:
    """
    Check if a language value represents Spanish.
    
    Handles various formats:
    - "Spanish", "spanish", "SPANISH"
    - "spa" (ISO 639-2)
    - "es" (ISO 639-1)
    - "Spanish (Español)"
    - "Español"
    """
    if not value:
        return False
    
    value_lower = value.lower().strip()
    
    # Direct matches
    spanish_values = [
        'spanish', 'spa', 'es', 'español', 'espanol',
        'spanish (español)', 'spanish (espanol)'
    ]
    
    if value_lower in spanish_values:
        return True
    
    # Partial matches (contains spanish or español)
    if 'spanish' in value_lower or 'español' in value_lower or 'espanol' in value_lower:
        return True
    
    return False


def verify_set_patient_language(traj, env_info, task_info):
    """
    Verify that the patient's language preference was set to Spanish.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', and 'subscores'
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
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    valid_languages = metadata.get('valid_language_values', ['spanish', 'Spanish', 'spa', 'es'])
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/set_language_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "language_updated": False,
            "language_is_spanish": False,
            "change_persisted": False,
            "vlm_verification": False
        }
        
        # Extract data from result
        patient = result.get('patient', {})
        language_data = result.get('language', {})
        validation = result.get('validation', {})
        
        patient_pid = patient.get('pid', 0)
        patient_fname = patient.get('fname', '')
        patient_lname = patient.get('lname', '')
        
        initial_language = language_data.get('initial', '')
        current_language = language_data.get('current', '')
        was_changed = language_data.get('was_changed', False)
        is_spanish = language_data.get('is_spanish', False)
        
        logger.info(f"Patient: {patient_fname} {patient_lname} (pid={patient_pid})")
        logger.info(f"Language: initial='{initial_language}', current='{current_language}'")
        logger.info(f"Changed: {was_changed}, Is Spanish: {is_spanish}")
        
        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient accessed (pid={expected_pid}, {patient_fname} {patient_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Language changed for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        # CRITERION 2: Language field was updated (25 points)
        # Anti-gaming: must have actually changed from initial value
        if was_changed and current_language and current_language != initial_language:
            score += 25
            subscores["language_updated"] = True
            feedback_parts.append(f"✅ Language field updated ('{initial_language}' → '{current_language}')")
        elif current_language and not initial_language:
            # Language was blank, now has value
            score += 25
            subscores["language_updated"] = True
            feedback_parts.append(f"✅ Language field set (was blank, now '{current_language}')")
        elif current_language == initial_language and initial_language:
            feedback_parts.append(f"⚠️ Language unchanged from initial value ('{initial_language}')")
            # Possible pre-existing value - agent may not have done anything
        else:
            feedback_parts.append(f"❌ Language field not updated (still '{current_language or 'blank'}')")
        
        # CRITERION 3: Language is Spanish (35 points) - Primary success criterion
        # Do our own verification in addition to export script's check
        language_verified_spanish = is_spanish_language(current_language) or is_spanish
        
        if language_verified_spanish:
            score += 35
            subscores["language_is_spanish"] = True
            feedback_parts.append(f"✅ Language correctly set to Spanish ('{current_language}')")
        else:
            if current_language:
                feedback_parts.append(f"❌ Language set to '{current_language}' (not Spanish)")
            else:
                feedback_parts.append("❌ Language field is empty/not set")
        
        # CRITERION 4: Change persisted to database (15 points)
        # Verified by the fact that export_result.sh queried the database
        if subscores["language_is_spanish"] and subscores["language_updated"]:
            score += 15
            subscores["change_persisted"] = True
            feedback_parts.append("✅ Change persisted to database")
        elif subscores["language_is_spanish"]:
            # Spanish but not changed from initial - might be pre-existing
            score += 5
            feedback_parts.append("⚠️ Language is Spanish but may have been pre-existing")
        
        # CRITERION 5: VLM Trajectory Verification (10 points)
        # Check that agent actually navigated through the UI
        vlm_score = verify_with_vlm(traj, env_info, expected_fname, expected_lname)
        if vlm_score > 0:
            score += vlm_score
            subscores["vlm_verification"] = True
            feedback_parts.append(f"✅ VLM verified workflow progression (+{vlm_score} pts)")
        else:
            feedback_parts.append("⚠️ VLM verification inconclusive")
        
        # Determine pass/fail
        # Must have language set to Spanish and be correct patient
        key_criteria_met = (
            subscores["correct_patient"] and 
            subscores["language_is_spanish"]
        )
        passed = score >= 75 and key_criteria_met
        
        # Final feedback
        if passed:
            feedback_parts.insert(0, "✅ TASK PASSED")
        else:
            if not subscores["language_is_spanish"]:
                feedback_parts.insert(0, "❌ TASK FAILED - Language not set to Spanish")
            else:
                feedback_parts.insert(0, f"❌ TASK FAILED - Score {score}/100 below threshold")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "initial_language": initial_language,
                "final_language": current_language,
                "language_is_spanish": language_verified_spanish
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {
                "correct_patient": False,
                "language_updated": False,
                "language_is_spanish": False,
                "change_persisted": False,
                "vlm_verification": False
            }
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
            "subscores": {
                "correct_patient": False,
                "language_updated": False,
                "language_is_spanish": False,
                "change_persisted": False,
                "vlm_verification": False
            }
        }
    except Exception as e:
        logger.exception(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "correct_patient": False,
                "language_updated": False,
                "language_is_spanish": False,
                "change_persisted": False,
                "vlm_verification": False
            }
        }


def verify_with_vlm(traj, env_info, expected_fname: str, expected_lname: str) -> int:
    """
    Use VLM to verify that the agent actually performed the workflow.
    
    Checks trajectory frames (not just final screenshot) to confirm:
    1. Agent logged into OpenEMR
    2. Agent searched for/accessed the patient
    3. Agent navigated to demographics
    4. Agent made changes and saved
    
    Returns:
        Points earned (0-10)
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from across the trajectory (not just final)
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if not frames and not final_frame:
            logger.warning("No frames available for VLM verification")
            return 0
        
        # Use trajectory frames for verification
        all_frames = frames + ([final_frame] if final_frame else [])
        
        prompt = f"""You are verifying if a computer agent successfully updated a patient's language preference in OpenEMR (an Electronic Health Records system).

TASK: Set the preferred language for patient {expected_fname} {expected_lname} to Spanish.

Analyze these screenshots from the agent's workflow and determine:
1. Did the agent log into OpenEMR? (login page, then dashboard/main screen)
2. Did the agent search for or access patient "{expected_fname} {expected_lname}"?
3. Did the agent navigate to demographics or patient editing screen?
4. Did the agent appear to make changes to a language field?
5. Did the agent save changes? (save button clicked, confirmation message, etc.)

Look for evidence of:
- OpenEMR interface (web-based EHR with patient data)
- Patient name "{expected_fname} {expected_lname}" visible
- Demographics or "Edit" screens
- Language dropdown or field
- Save/Update buttons or confirmation messages

Respond in JSON format:
{{
    "logged_in": true/false,
    "patient_accessed": true/false,
    "demographics_screen": true/false,
    "language_field_visible": true/false,
    "changes_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}}"""
        
        vlm_result = query_vlm(
            prompt=prompt,
            images=all_frames
        )
        
        if not vlm_result.get("success"):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get("parsed", {})
        
        # Score based on workflow steps observed
        vlm_points = 0
        
        if parsed.get("logged_in"):
            vlm_points += 2
        if parsed.get("patient_accessed"):
            vlm_points += 3
        if parsed.get("demographics_screen") or parsed.get("language_field_visible"):
            vlm_points += 3
        if parsed.get("changes_saved"):
            vlm_points += 2
        
        # Cap at 10 points
        vlm_points = min(vlm_points, 10)
        
        # Reduce points for low confidence
        confidence = parsed.get("confidence", "low")
        if confidence == "low":
            vlm_points = vlm_points // 2
        elif confidence == "medium":
            vlm_points = int(vlm_points * 0.75)
        
        logger.info(f"VLM verification result: {parsed}")
        logger.info(f"VLM points awarded: {vlm_points}")
        
        return vlm_points
        
    except ImportError:
        logger.warning("gym_anything.vlm not available for VLM verification")
        return 0
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return 0


if __name__ == "__main__":
    # Test mode - run with mock data
    print("Verifier module loaded successfully")
    print("Use verify_set_patient_language(traj, env_info, task_info) to verify")