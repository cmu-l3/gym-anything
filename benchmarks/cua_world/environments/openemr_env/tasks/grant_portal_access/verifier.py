#!/usr/bin/env python3
"""
Verifier for Grant Patient Portal Access task in OpenEMR

Verification Strategy:
1. PRIMARY: Query database for portal access fields
2. SECONDARY: VLM verification of workflow via trajectory screenshots

Scoring (100 points total):
- Correct patient selected (pid=2): 20 points
- Portal access enabled (allow_patient_portal='YES'): 35 points
- Portal username set to 'angila.fadel': 25 points
- Record was modified during task: 10 points
- VLM confirms workflow completion: 10 points

Passing threshold: 70 points with portal_enabled criterion met
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_grant_portal_access(traj, env_info, task_info):
    """
    Verify that patient portal access was correctly granted.

    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 2)
    expected_fname = metadata.get('patient_fname', 'Angila')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_portal_status = metadata.get('expected_portal_status', 'YES')
    expected_username = metadata.get('expected_portal_username', 'angila.fadel')

    score = 0
    feedback_parts = []
    subscores = {
        "correct_patient": False,
        "portal_enabled": False,
        "username_correct": False,
        "record_modified": False,
        "workflow_visible": False
    }

    # =========================================================================
    # PRIMARY VERIFICATION: Database check via exported JSON
    # =========================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/portal_access_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        logger.info(f"Loaded result data: {result}")

        # Extract data
        patient_pid = result.get('patient_pid', 0)
        portal_status = result.get('portal_status', {})
        validation = result.get('validation', {})
        task_duration = result.get('task_duration_seconds', 0)

        portal_enabled = portal_status.get('portal_enabled', False)
        portal_username = portal_status.get('portal_username', '')
        username_matches = portal_status.get('username_matches_expected', False)
        record_modified = validation.get('record_modified', False)

        logger.info(f"Patient PID: {patient_pid}, Portal enabled: {portal_enabled}, Username: {portal_username}")

        # CRITERION 1: Correct patient (20 points)
        if patient_pid == expected_pid:
            score += 20
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient ID: expected {expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Portal access configured for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: Portal access enabled (35 points)
        if portal_enabled:
            score += 35
            subscores["portal_enabled"] = True
            feedback_parts.append("✅ Patient portal access is ENABLED")
        else:
            allow_value = portal_status.get('allow_patient_portal', '')
            feedback_parts.append(f"❌ Patient portal access NOT enabled (value: '{allow_value}')")

        # CRITERION 3: Portal username correct (25 points)
        if username_matches:
            score += 25
            subscores["username_correct"] = True
            feedback_parts.append(f"✅ Portal username correctly set to '{expected_username}'")
        elif portal_username:
            # Partial credit if username is set but different
            score += 10
            feedback_parts.append(f"⚠️ Portal username set to '{portal_username}' (expected '{expected_username}')")
        else:
            feedback_parts.append("❌ Portal username not set")

        # CRITERION 4: Record was modified during task (10 points) - anti-gaming
        if record_modified:
            score += 10
            subscores["record_modified"] = True
            feedback_parts.append("✅ Record was modified during task execution")
        else:
            feedback_parts.append("⚠️ Could not confirm record modification during task")

    except FileNotFoundError:
        feedback_parts.append("❌ Export result file not found - task may not have completed")
        logger.error("Result file not found")
    except json.JSONDecodeError as e:
        feedback_parts.append(f"❌ Failed to parse export result: {e}")
        logger.error(f"JSON decode error: {e}")
    except Exception as e:
        feedback_parts.append(f"❌ Verification error: {e}")
        logger.error(f"Unexpected error: {e}")

    # =========================================================================
    # SECONDARY VERIFICATION: VLM trajectory check (10 points)
    # =========================================================================
    try:
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            # Sample frames from trajectory to verify workflow
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                vlm_prompt = """You are verifying if a computer agent successfully enabled patient portal access in OpenEMR.

The task was to:
1. Find patient Angila Fadel
2. Edit her demographics
3. Enable patient portal access
4. Set portal username to 'angila.fadel'
5. Save the changes

Look at these screenshots from the task execution and determine:
1. Did the agent navigate to a patient demographics/edit screen?
2. Is there evidence of portal settings being modified?
3. Did the agent appear to save/submit changes?

Respond in JSON format:
{
    "demographics_screen_visible": true/false,
    "portal_settings_visible": true/false,
    "save_action_observed": true/false,
    "patient_name_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
                all_frames = frames + ([final_frame] if final_frame else [])
                
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=all_frames[:6]  # Limit to 6 images
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    demographics_visible = parsed.get("demographics_screen_visible", False)
                    portal_visible = parsed.get("portal_settings_visible", False)
                    save_observed = parsed.get("save_action_observed", False)
                    confidence = parsed.get("confidence", "low")
                    
                    # Award points for workflow evidence
                    workflow_points = 0
                    if demographics_visible:
                        workflow_points += 3
                    if portal_visible:
                        workflow_points += 4
                    if save_observed:
                        workflow_points += 3
                    
                    if workflow_points > 0:
                        score += min(workflow_points, 10)
                        subscores["workflow_visible"] = workflow_points >= 5
                        feedback_parts.append(f"✅ VLM confirmed workflow steps ({confidence} confidence)")
                    else:
                        feedback_parts.append("⚠️ VLM could not confirm workflow completion")
                else:
                    feedback_parts.append("⚠️ VLM verification unavailable")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM verification")
        else:
            feedback_parts.append("ℹ️ VLM verification not available")
            
    except ImportError:
        feedback_parts.append("ℹ️ VLM module not available")
        logger.warning("Could not import VLM utilities")
    except Exception as e:
        feedback_parts.append(f"⚠️ VLM verification failed: {e}")
        logger.warning(f"VLM verification error: {e}")

    # =========================================================================
    # FINAL SCORING
    # =========================================================================
    
    # Key criteria: portal must be enabled AND correct patient
    key_criteria_met = subscores["correct_patient"] and subscores["portal_enabled"]
    
    # Passing threshold: 70 points with key criteria met
    passed = score >= 70 and key_criteria_met

    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        feedback = f"PASSED (Score: {score}/100) - Patient portal access successfully granted. {feedback}"
    elif subscores["correct_patient"] and not subscores["portal_enabled"]:
        feedback = f"FAILED (Score: {score}/100) - Portal access not enabled. {feedback}"
    else:
        feedback = f"FAILED (Score: {score}/100) - {feedback}"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})",
            "expected_username": expected_username,
            "portal_enabled": subscores["portal_enabled"],
            "username_correct": subscores["username_correct"]
        }
    }