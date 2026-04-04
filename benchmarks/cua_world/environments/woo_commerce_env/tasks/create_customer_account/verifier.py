#!/usr/bin/env python3
"""
Verifier for Create Customer Account task in WooCommerce.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. Customer exists in database (15 pts)
  2. Email matches expected value (10 pts)
  3. First name matches (10 pts)
  4. Last name matches (10 pts)
  5. Username matches (10 pts)
  6. Role is 'customer' (10 pts)
  7. Customer was newly created (5 pts)

VLM checks (30 points) — using TRAJECTORY frames (framework-captured):
  8. Process verification (15 pts): Sampled trajectory frames show the agent
     navigating to Users > Add New, filling user form, and creating account.
  9. Final state verification (10 pts): Final frame shows user created
     or success message.
  10. Cross-validation (5 pts): Programmatic customer found agrees with VLM
      seeing account creation workflow.

Pass threshold: 55 points AND customer found AND VLM trajectory confirms workflow
(when VLM is available)
"""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM HELPERS
# ================================================================

def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images. Returns parsed dict or None."""
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


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a customer account in a WooCommerce store via the WordPress admin interface.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful customer account creation, the agent should progress through these stages:
1. WordPress admin dashboard visible (already logged in)
2. Navigation to Users section (Users > Add New)
3. User form being filled in (username, email, first name, last name, role selection)
4. Role set to "Customer" (WooCommerce customer role)
5. User created (success message or user visible in user list)

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through navigating to user creation AND filling in details?
2. USER_FORM_VISIBLE: At any point, is the WordPress "Add New User" form visible with fields being filled?
3. CREATION_CONFIRMED: Is there evidence the user was created (success message, user list showing new user)?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes (not the same screen repeated)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "user_form_visible": true/false,
    "creation_confirmed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce customer account creation task.

This is a desktop screenshot showing the WordPress admin interface in a browser.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible (not the login page)?
2. SUCCESS_INDICATORS: Are there any success indicators? (e.g., "New user created" message, user profile page, user visible in users list)
3. USER_DATA_VISIBLE: Can you see any user details (name, email, username)?
4. ERROR_INDICATORS: Are there any error messages or warnings?

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


def verify_create_customer_account(traj, env_info, task_info):
    """
    Verify that the expected customer account was created in WooCommerce.

    Scoring (100 points total):
    Programmatic (70 pts): customer exists, email, firstname, lastname, username, role, newly created
    VLM (30 pts): trajectory process (15), final state (10), cross-validation (5)

    Pass threshold: 55 points AND customer found AND
    (VLM confirms workflow OR VLM unavailable)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_firstname = metadata.get('expected_firstname', 'Sarah')
    expected_lastname = metadata.get('expected_lastname', 'Johnson')
    expected_email = metadata.get('expected_email', 'sarah.johnson@example.com')
    expected_username = metadata.get('expected_username', 'sarahjohnson')
    expected_role = metadata.get('expected_role', 'customer')

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Load result file from container
    # ================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_customer_result.json", temp_result.name)
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

    initial_count = result.get('initial_customer_count', 0)
    current_count = result.get('current_customer_count', 0)
    customer_found = result.get('customer_found', False)
    customer = result.get('customer', {})

    logger.info(f"Result: initial={initial_count}, current={current_count}, found={customer_found}")
    logger.info(f"Customer data: {customer}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: Customer exists in database (15 points)
    if customer_found:
        score += 15
        feedback_parts.append("Customer found in database")
    else:
        feedback_parts.append("Customer NOT found in database")
        if current_count > initial_count:
            feedback_parts.append(f"Note: {current_count - initial_count} new customer(s) added but not matching")
        else:
            feedback_parts.append("No new customers were added")

    # Criterion 2: Email matches (10 points)
    email = customer.get('email', '')
    email_correct = email.strip().lower() == expected_email.strip().lower()
    if email_correct:
        score += 10
        feedback_parts.append(f"Email correct: {expected_email}")
    elif email:
        feedback_parts.append(f"Email mismatch: expected '{expected_email}', got '{email}'")
    else:
        feedback_parts.append("Email not set")

    # Criterion 3: First name matches (10 points) - EXACT match only (no partial credit)
    firstname = customer.get('first_name', '')
    firstname_correct = firstname.strip().lower() == expected_firstname.strip().lower()
    if firstname_correct:
        score += 10
        feedback_parts.append(f"First name correct: {expected_firstname}")
    elif firstname:
        feedback_parts.append(f"First name mismatch: expected '{expected_firstname}', got '{firstname}'")
    else:
        feedback_parts.append("First name not set")

    # Criterion 4: Last name matches (10 points) - EXACT match only (no partial credit)
    lastname = customer.get('last_name', '')
    lastname_correct = lastname.strip().lower() == expected_lastname.strip().lower()
    if lastname_correct:
        score += 10
        feedback_parts.append(f"Last name correct: {expected_lastname}")
    elif lastname:
        feedback_parts.append(f"Last name mismatch: expected '{expected_lastname}', got '{lastname}'")
    else:
        feedback_parts.append("Last name not set")

    # Criterion 5: Username matches (10 points) - EXACT match only (no partial credit)
    username = customer.get('username', '')
    username_correct = username.strip().lower() == expected_username.strip().lower()
    if username_correct:
        score += 10
        feedback_parts.append(f"Username correct: {expected_username}")
    elif username:
        feedback_parts.append(f"Username mismatch: expected '{expected_username}', got '{username}'")
    else:
        feedback_parts.append("Username not set")

    # Criterion 6: Role is 'customer' (10 points)
    # WordPress stores roles as serialized PHP: a:1:{s:8:"customer";b:1;}
    # Use precise regex to match exact role name, not substring (e.g., "customer_vip" should not match "customer")
    role_capabilities = customer.get('role_capabilities', '')
    role_correct = False
    if role_capabilities:
        # Match the serialized PHP pattern: s:N:"role_name";b:1;
        # This ensures exact role name matching within the serialized string
        role_pattern = re.compile(
            r'"' + re.escape(expected_role.lower()) + r'";b:1;',
            re.IGNORECASE
        )
        role_correct = bool(role_pattern.search(role_capabilities))
    if role_correct:
        score += 10
        feedback_parts.append(f"Role correct: {expected_role}")
    elif role_capabilities:
        feedback_parts.append(f"Role mismatch: expected '{expected_role}' in capabilities, got '{role_capabilities}'")
    else:
        feedback_parts.append("Role not set or not retrieved")

    # Criterion 7: Customer was newly created (5 points)
    newly_created = current_count > initial_count
    if newly_created:
        score += 5
        feedback_parts.append("Customer count increased (newly created)")
    else:
        feedback_parts.append("Customer count unchanged")

    # ================================================================
    # VLM CHECKS (30 points total)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False

    sampled_frames = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        # --- VLM Check A: Process Verification — 15 points ---
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
                    feedback_parts.append("VLM process: Full workflow progression confirmed")
                elif workflow_ok or form_visible:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression but workflow unclear")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient trajectory frames")

        # --- VLM Check B: Final State Verification — 10 points ---
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
                    feedback_parts.append("VLM final: Admin visible with success indicators")
                elif admin_ok and success_ok:
                    score += 7
                    feedback_parts.append("VLM final: Success indicators with warnings")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible but no success indicators")
                else:
                    feedback_parts.append("VLM final: Admin interface not visible")
            else:
                feedback_parts.append("VLM final state check failed")
        else:
            feedback_parts.append("VLM final: No final frame available")

        # --- VLM Check C: Cross-validation — 5 points ---
        if customer_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: DB customer + VLM workflow agree")
            details['cross_validation'] = 'pass'
        elif customer_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch: customer in DB but workflow not confirmed by VLM")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not customer_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees workflow but customer not in DB")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        # VLM not available — no free points, just note it
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================

    # Must have customer found AND score >= 55
    # When VLM is available, must also have VLM confirmation
    if vlm_available:
        passed = score >= 55 and customer_found and vlm_workflow_confirmed
    else:
        passed = score >= 55 and customer_found

    details.update({
        "customer_found": customer_found,
        "email_correct": email_correct,
        "firstname_correct": firstname_correct,
        "lastname_correct": lastname_correct,
        "username_correct": username_correct,
        "role_correct": role_correct,
        "newly_created": newly_created,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
