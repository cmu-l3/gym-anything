#!/usr/bin/env python3
"""
Verifier for Create User task in WordPress.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. User exists in database (15 pts)
  2. Username matches expected (10 pts)
  3. Email matches expected (10 pts)
  4. First name matches expected (10 pts)
  5. Last name matches expected (10 pts)
  6. Role is Editor (10 pts)
  7. User was newly created (5 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  8. Process verification (15 pts): Frames show user creation workflow
  9. Final state verification (10 pts): Final frame shows success
  10. Cross-validation (5 pts): DB agrees with VLM

Pass threshold: 70 points AND user found AND username correct
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images."""
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a new user in WordPress admin.

For successful user creation, the agent should:
1. Navigate to Users menu in WordPress admin
2. Click "Add New" to access the new user form
3. Fill in username, email, name fields
4. Select a role (Editor)
5. Click "Add New User" button

Assess:
1. WORKFLOW_COMPLETED: Did the agent navigate to user form AND fill in details?
2. USER_FORM_VISIBLE: Is the WordPress "Add New User" form visible with fields being filled?
3. SUBMIT_CONFIRMED: Is there evidence the user was created (Add New User clicked, success message)?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "user_form_visible": true/false,
    "submit_confirmed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress user creation task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. SUCCESS_INDICATORS: Are there success indicators? (e.g., "New user created" message, user list showing new user)
3. USER_DATA_VISIBLE: Can you see user details that were entered?
4. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "user_data_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_create_user(traj, env_info, task_info):
    """
    Verify that the expected user was created in WordPress.

    Scoring (100 points total):
    Programmatic (70 pts): user exists, username, email, name, role, newly created
    VLM (30 pts): trajectory process (15), final state (10), cross-validation (5)

    Pass threshold: 70 points AND user found AND username correct
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_username = metadata.get('expected_username', 'marketing_lead')
    expected_email = metadata.get('expected_email', 'marketing@example.com')
    expected_first_name = metadata.get('expected_first_name', 'Sarah')
    expected_last_name = metadata.get('expected_last_name', 'Johnson')
    expected_role = metadata.get('expected_role', 'editor')

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_user_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False, "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    initial_count = result.get('initial_user_count', 0)
    current_count = result.get('current_user_count', 0)
    user_found = result.get('user_found', False)
    user = result.get('user', {})

    logger.info(f"Result: initial={initial_count}, current={current_count}, found={user_found}")
    logger.info(f"User data: {user}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: User exists (15 points)
    if user_found:
        score += 15
        feedback_parts.append("User found in database")
    else:
        feedback_parts.append("User NOT found in database")
        if current_count > initial_count:
            feedback_parts.append(f"Note: {current_count - initial_count} new user(s) but not matching expected")
        else:
            feedback_parts.append("No new users were added")

    # Criterion 2: Username matches EXACTLY (10 points) - REQUIRED
    # NO partial credit - username must match exactly
    username = user.get('username', '')
    username_correct = username.strip().lower() == expected_username.strip().lower()
    if username_correct:
        score += 10
        feedback_parts.append(f"Username correct: {expected_username}")
    elif username:
        feedback_parts.append(f"Username WRONG: expected '{expected_username}', got '{username}'")
    else:
        feedback_parts.append("Username not set")

    # Criterion 3: Email matches (10 points)
    email = user.get('email', '')
    email_correct = email.strip().lower() == expected_email.strip().lower()
    if email_correct:
        score += 10
        feedback_parts.append(f"Email correct: {expected_email}")
    elif email:
        feedback_parts.append(f"Email mismatch: expected '{expected_email}', got '{email}'")
    else:
        feedback_parts.append("Email not set")

    # Criterion 4: First name matches (10 points)
    first_name = user.get('first_name', '')
    first_name_correct = first_name.strip().lower() == expected_first_name.strip().lower()
    if first_name_correct:
        score += 10
        feedback_parts.append(f"First name correct: {expected_first_name}")
    elif first_name:
        feedback_parts.append(f"First name mismatch: expected '{expected_first_name}', got '{first_name}'")
    else:
        feedback_parts.append("First name not set")

    # Criterion 5: Last name matches (10 points)
    last_name = user.get('last_name', '')
    last_name_correct = last_name.strip().lower() == expected_last_name.strip().lower()
    if last_name_correct:
        score += 10
        feedback_parts.append(f"Last name correct: {expected_last_name}")
    elif last_name:
        feedback_parts.append(f"Last name mismatch: expected '{expected_last_name}', got '{last_name}'")
    else:
        feedback_parts.append("Last name not set")

    # Criterion 6: Role is Editor (10 points)
    role = user.get('role', '')
    role_correct = expected_role.lower() in role.lower() if role else False
    if role_correct:
        score += 10
        feedback_parts.append(f"Role correct: {expected_role}")
    elif role:
        feedback_parts.append(f"Role mismatch: expected '{expected_role}', got '{role}'")
    else:
        feedback_parts.append("Role not set")

    # Criterion 7: User was newly created (5 points)
    newly_created = current_count > initial_count
    if newly_created:
        score += 5
        feedback_parts.append("User count increased (newly created)")
    else:
        feedback_parts.append("User count unchanged")

    # ================================================================
    # VLM CHECKS (30 points total)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False
    vlm_query_failed = False  # Track if VLM queries failed (not just unavailable)

    sampled_frames = sample_frames(traj, num_samples=12) if sample_frames else []  # Increased from 6 to 12
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        # VLM Check A: Process Verification (15 points)
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                form_visible = process_result.get('user_form_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Full workflow confirmed")
                elif workflow_ok or form_visible:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                vlm_query_failed = True
                feedback_parts.append("VLM process check failed (query error)")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

        # VLM Check B: Final State (10 points)
        if has_final:
            final_result = _vlm_query(
                query_vlm, FINAL_STATE_PROMPT, image=final_frame
            )
            details['vlm_final_state'] = final_result

            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                success_ok = final_result.get('success_indicators', False)
                error_found = final_result.get('error_indicators', False)

                if admin_ok and success_ok and not error_found:
                    score += 10
                    feedback_parts.append("VLM final: Success confirmed")
                elif admin_ok and success_ok:
                    score += 7
                    feedback_parts.append("VLM final: Success with warnings")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible")
                else:
                    feedback_parts.append("VLM final: Admin not visible")
            else:
                feedback_parts.append("VLM final check failed")
        else:
            feedback_parts.append("VLM final: No frame")

        # VLM Check C: Cross-validation (5 points)
        if user_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: DB + VLM agree")
            details['cross_validation'] = 'pass'
        elif user_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation: User in DB but VLM didn't confirm")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not user_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees creation but user not in DB")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        feedback_parts.append("VLM checks skipped")

    # ================================================================
    # PASS CRITERIA - STRICTER
    # ================================================================
    # Must have:
    # - Score >= 70
    # - User found
    # - Username correct (exact match required)
    # VLM confirmation is OPTIONAL - only required if VLM successfully processed
    # (If VLM query failed, don't penalize the agent for it)

    # VLM is only required for pass if:
    # 1. VLM is available AND
    # 2. VLM query did NOT fail (returned a result)
    vlm_required_for_pass = vlm_available and not vlm_query_failed

    if vlm_required_for_pass:
        passed = (score >= 70 and user_found and username_correct and
                  vlm_workflow_confirmed)
    else:
        passed = score >= 70 and user_found and username_correct

    details.update({
        "user_found": user_found,
        "username_correct": username_correct,
        "email_correct": email_correct,
        "first_name_correct": first_name_correct,
        "last_name_correct": last_name_correct,
        "role_correct": role_correct,
        "newly_created": newly_created,
        "vlm_available": vlm_available,
        "vlm_query_failed": vlm_query_failed,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
