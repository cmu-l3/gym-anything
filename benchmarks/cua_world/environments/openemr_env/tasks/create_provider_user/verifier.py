#!/usr/bin/env python3
"""
Verifier for Create Provider User task in OpenEMR

Verifies that a new authorized provider user was correctly created.

Scoring (100 points total):
- User record exists with correct username: 25 points
- Correct first and last name: 20 points  
- Authorized flag set (can sign documents): 25 points
- Active flag set (account enabled): 10 points
- NPI recorded: 10 points
- Created during task (anti-gaming): 10 points

Pass threshold: 70 points with both user_exists AND authorized_flag required
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_provider_user(traj, env_info, task_info):
    """
    Verify that the expected provider user was created in OpenEMR.

    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata containing expected values

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_username = metadata.get('expected_username', 'jsmith_np')
    expected_fname = metadata.get('expected_fname', 'Jennifer')
    expected_lname = metadata.get('expected_lname', 'Smith')
    expected_npi = metadata.get('expected_npi', '1234567890')
    pass_threshold = metadata.get('pass_threshold', 70)

    # Scoring weights
    weights = metadata.get('scoring_weights', {})
    weight_user_exists = weights.get('user_exists', 25)
    weight_name_correct = weights.get('name_correct', 20)
    weight_authorized = weights.get('authorized_flag', 25)
    weight_active = weights.get('active_flag', 10)
    weight_npi = weights.get('npi_recorded', 10)
    weight_created = weights.get('created_during_task', 10)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_provider_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "user_exists": False,
            "name_correct": False,
            "authorized_flag": False,
            "active_flag": False,
            "npi_recorded": False,
            "created_during_task": False
        }

        # Extract data from result
        user_found = result.get('user_found', False)
        user = result.get('user', {})
        validation = result.get('validation', {})
        initial_state = result.get('initial_state', {})
        current_state = result.get('current_state', {})

        logger.info(f"User found: {user_found}")
        logger.info(f"User data: {user}")
        logger.info(f"Validation: {validation}")

        # CRITERION 1: User exists with correct username (25 points)
        if user_found:
            actual_username = user.get('username', '')
            if actual_username.lower() == expected_username.lower():
                score += weight_user_exists
                subscores["user_exists"] = True
                feedback_parts.append(f"✅ User '{expected_username}' found in database")
            else:
                feedback_parts.append(f"❌ Username mismatch: expected '{expected_username}', got '{actual_username}'")
        else:
            feedback_parts.append(f"❌ User '{expected_username}' NOT found in database")
            
            # Check if any new users were added
            initial_count = initial_state.get('user_count', 0)
            current_count = current_state.get('user_count', 0)
            if current_count > initial_count:
                new_users = current_count - initial_count
                feedback_parts.append(f"   Note: {new_users} new user(s) created, but not with expected username")
            else:
                feedback_parts.append("   No new users were created during the task")

            # Early return - can't verify other criteria without user
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {
                    "initial_state": initial_state,
                    "current_state": current_state
                }
            }

        # CRITERION 2: Correct first and last name (20 points)
        actual_fname = user.get('fname', '').strip()
        actual_lname = user.get('lname', '').strip()
        
        fname_match = actual_fname.lower() == expected_fname.lower()
        lname_match = actual_lname.lower() == expected_lname.lower()
        
        if fname_match and lname_match:
            score += weight_name_correct
            subscores["name_correct"] = True
            feedback_parts.append(f"✅ Name correct: {actual_fname} {actual_lname}")
        else:
            if fname_match:
                score += weight_name_correct // 2
                feedback_parts.append(f"⚠️ First name correct ({actual_fname}), last name wrong (expected '{expected_lname}', got '{actual_lname}')")
            elif lname_match:
                score += weight_name_correct // 2
                feedback_parts.append(f"⚠️ Last name correct ({actual_lname}), first name wrong (expected '{expected_fname}', got '{actual_fname}')")
            else:
                feedback_parts.append(f"❌ Name incorrect: expected '{expected_fname} {expected_lname}', got '{actual_fname} {actual_lname}'")

        # CRITERION 3: Authorized flag set (25 points) - CRITICAL
        authorized = user.get('authorized', '0')
        # Handle both string and int representations
        is_authorized = str(authorized) == '1' or authorized == 1 or authorized == True
        
        if is_authorized:
            score += weight_authorized
            subscores["authorized_flag"] = True
            feedback_parts.append("✅ Authorized flag SET - user can sign clinical documents")
        else:
            feedback_parts.append("❌ Authorized flag NOT set - user CANNOT sign clinical documents (CRITICAL)")
            # This is a critical failure - provider without authorization is useless

        # CRITERION 4: Active flag set (10 points)
        active = user.get('active', '0')
        is_active = str(active) == '1' or active == 1 or active == True
        
        if is_active:
            score += weight_active
            subscores["active_flag"] = True
            feedback_parts.append("✅ Active flag SET - account is enabled")
        else:
            feedback_parts.append("❌ Active flag NOT set - account is disabled")

        # CRITERION 5: NPI recorded (10 points)
        actual_npi = user.get('npi', '').strip()
        if actual_npi and actual_npi.lower() not in ['null', 'none', '']:
            score += weight_npi
            subscores["npi_recorded"] = True
            if actual_npi == expected_npi:
                feedback_parts.append(f"✅ NPI recorded correctly: {actual_npi}")
            else:
                feedback_parts.append(f"✅ NPI recorded: {actual_npi} (expected {expected_npi})")
        else:
            feedback_parts.append("❌ NPI not recorded")

        # CRITERION 6: Created during task - anti-gaming (10 points)
        created_during = validation.get('created_during_task', False)
        if created_during:
            score += weight_created
            subscores["created_during_task"] = True
            feedback_parts.append("✅ User was newly created during this task")
        else:
            # Check by comparing user ID to initial max
            user_id = int(user.get('id', 0)) if user.get('id') else 0
            initial_max_id = initial_state.get('max_user_id', 0)
            
            if user_id > initial_max_id:
                score += weight_created
                subscores["created_during_task"] = True
                feedback_parts.append(f"✅ User created during task (ID {user_id} > initial max {initial_max_id})")
            else:
                feedback_parts.append(f"⚠️ User may have pre-existed (ID {user_id} <= initial max {initial_max_id})")

        # Determine pass/fail
        # Key criteria: user must exist AND be authorized
        key_criteria_met = subscores["user_exists"] and subscores["authorized_flag"]
        passed = score >= pass_threshold and key_criteria_met

        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback = f"✅ PASSED (Score: {score}/100) | " + feedback
        else:
            if not key_criteria_met:
                if not subscores["user_exists"]:
                    feedback = f"❌ FAILED - User not created | " + feedback
                elif not subscores["authorized_flag"]:
                    feedback = f"❌ FAILED - Authorized flag not set (critical requirement) | " + feedback
            else:
                feedback = f"❌ FAILED (Score: {score}/100, need {pass_threshold}) | " + feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "user": user,
                "initial_state": initial_state,
                "current_state": current_state,
                "key_criteria_met": key_criteria_met
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Verification failed - result file not found. Export script may have failed.",
            "subscores": {
                "user_exists": False,
                "name_correct": False,
                "authorized_flag": False,
                "active_flag": False,
                "npi_recorded": False,
                "created_during_task": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification failed - could not parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {}
        }


# Additional helper for VLM-based verification (optional secondary check)
def verify_via_vlm(traj, env_info):
    """
    Optional VLM-based verification using trajectory screenshots.
    
    Checks if the agent navigated to user management and created a user.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        query_vlm = env_info.get('query_vlm')
        if not query_vlm:
            return {"success": False, "error": "VLM not available"}
        
        # Sample frames from trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "error": "No screenshots available"}
        
        prompt = """You are verifying if a computer agent successfully created a new user in OpenEMR.

TASK: Create a new authorized provider user named "Jennifer Smith" with username "jsmith_np".

Look at these screenshots showing the agent's workflow and determine:
1. Did the agent navigate to Administration > Users?
2. Did the agent click "Add User" or similar button?
3. Did the agent fill in user details (name, username, etc.)?
4. Was the "Authorized" checkbox visible and checked?
5. Does the final screen show a user list or success message?
6. Is "Jennifer Smith" or "jsmith_np" visible in the final state?

Respond in JSON format:
{
    "navigated_to_users": true/false,
    "add_user_clicked": true/false,
    "form_filled": true/false,
    "authorized_checked": true/false,
    "user_appears_created": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        all_images = frames + ([final] if final else [])
        result = query_vlm(prompt=prompt, images=all_images)
        
        return result
        
    except ImportError:
        return {"success": False, "error": "VLM module not available"}
    except Exception as e:
        return {"success": False, "error": str(e)}