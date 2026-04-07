#!/usr/bin/env python3
"""
Verifier for bulk_import_intranet_users task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points):
  1. Role Creation: 'employee' exists (10 pts)
  2. Role Capabilities: exactly the expected 3 caps (10 pts)
  3. Role Cleanup: 'subscriber' deleted (10 pts)
  4. User Count: exactly 25 users have the 'employee' role (15 pts)
  5. Core User Data: spot checked users have correct email, first, last name (15 pts)
  6. User Metadata: spot checked users have correct 'department' meta (10 pts)

VLM checks (30 points):
  7. Process verification: frames show CSV processing or admin import workflow (15 pts)
  8. Final state: final frame shows user list or success (10 pts)
  9. Cross-validation (5 pts)

Pass threshold: 70 points AND (employee_count >= 20) AND role created
"""

import json
import tempfile
import os
import logging
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
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

TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots of an agent importing users into a WordPress site.
The agent might be using a terminal (WP-CLI or Bash scripts) or a WordPress plugin via the browser to process a CSV file.

Assess:
1. WORKFLOW_COMPLETED: Is there evidence of processing the CSV file or bulk creating users?
2. TERMINAL_OR_PLUGIN_USED: Is the agent using a terminal script or an import plugin interface?
3. SCRIPTING_EVIDENCE: If using terminal, do you see commands related to reading the CSV, creating roles, or looping over users?
4. MEANINGFUL_PROGRESSION: Do the frames show progression of the task?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "terminal_or_plugin_used": true/false,
    "scripting_evidence": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress bulk user import task.

Assess:
1. ADMIN_OR_TERMINAL_VISIBLE: Is the WordPress admin user list or a completed terminal script visible?
2. SUCCESS_INDICATORS: Are there newly imported users visible in the UI or success logs in the terminal?
3. ERROR_INDICATORS: Any errors visible?

Respond in JSON format:
{
    "admin_or_terminal_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def verify_bulk_import(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Expected metadata
    metadata = task_info.get('metadata', {})
    expected_caps = set(metadata.get('expected_role_caps', ["read", "read_private_posts", "read_private_pages"]))
    expected_count = metadata.get('expected_user_count', 25)
    spot_checks_expected = metadata.get('spot_check_users', {})

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/bulk_import_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    roles_data = result.get('roles', {})
    counts_data = result.get('counts', {})
    spot_data = result.get('spot_checks', {})
    
    # 1. Role Creation (10 pts)
    employee_exists = roles_data.get('employee_exists', False)
    if employee_exists:
        score += 10
        feedback_parts.append("Role 'employee' created")
    else:
        feedback_parts.append("FAIL: Role 'employee' not found")

    # 2. Role Capabilities (10 pts)
    # The caps dict from WP looks like {"read": True, "read_private_posts": True, "level_0": True}
    # We want to make sure the expected ones are true, and nothing else significant is granted.
    raw_caps = roles_data.get('employee_caps', {})
    actual_caps = {k for k, v in raw_caps.items() if v is True and not k.startswith('level_')}
    
    if employee_exists:
        if actual_caps == expected_caps:
            score += 10
            feedback_parts.append("Capabilities strictly correct")
        elif expected_caps.issubset(actual_caps):
            score += 5
            feedback_parts.append(f"Capabilities contain expected, but also extra: {actual_caps - expected_caps}")
        else:
            feedback_parts.append(f"Capabilities incorrect. Expected: {expected_caps}, Got: {actual_caps}")

    # 3. Role Cleanup (10 pts)
    subscriber_exists = roles_data.get('subscriber_exists', True)
    if not subscriber_exists:
        score += 10
        feedback_parts.append("Role 'subscriber' successfully deleted")
    else:
        feedback_parts.append("FAIL: Role 'subscriber' still exists")

    # 4. User Count (15 pts)
    employee_count = int(counts_data.get('employee_count', 0))
    if employee_count == expected_count:
        score += 15
        feedback_parts.append(f"Exactly {expected_count} users have employee role")
    elif employee_count > 0:
        pct = min(1.0, employee_count / expected_count)
        pts = int(15 * pct)
        score += pts
        feedback_parts.append(f"Partial user import: {employee_count}/{expected_count} users")
    else:
        feedback_parts.append("FAIL: No users assigned to employee role")

    # 5 & 6. Spot Checks Core (15 pts) & Meta (10 pts)
    core_pts_per_user = 5
    meta_pts_per_user = 10 / len(spot_checks_expected) if spot_checks_expected else 0
    
    all_core_correct = True
    all_meta_correct = True
    users_checked = 0

    for username, expected in spot_checks_expected.items():
        user_actual = spot_data.get(username, {})
        if user_actual.get('found', False):
            users_checked += 1
            # Core checks
            core_ok = (
                user_actual.get('email', '').lower() == expected.get('email', '').lower() and
                user_actual.get('first_name', '') == expected.get('first_name', '') and
                user_actual.get('last_name', '') == expected.get('last_name', '')
            )
            if core_ok:
                score += core_pts_per_user
            else:
                all_core_correct = False
            
            # Meta check
            if user_actual.get('department', '') == expected.get('department', ''):
                score += meta_pts_per_user
            else:
                all_meta_correct = False
        else:
            all_core_correct = False
            all_meta_correct = False

    if users_checked == len(spot_checks_expected):
        if all_core_correct:
            feedback_parts.append("Spot checks: Core data accurate")
        else:
            feedback_parts.append("Spot checks: Some core data mismatched")
            
        if all_meta_correct:
            feedback_parts.append("Spot checks: Department metadata accurate")
        else:
            feedback_parts.append("Spot checks: Some department metadata mismatched")
    elif users_checked > 0:
        feedback_parts.append(f"Spot checks: Only {users_checked}/{len(spot_checks_expected)} sample users found")
    else:
        feedback_parts.append("FAIL: None of the spot-check sample users were found")

    # VLM Evaluation (30 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        # Process verification (15 pts)
        process_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
        if process_res and process_res.get("workflow_completed"):
            vlm_score += 10
            if process_res.get("meaningful_progression"):
                vlm_score += 5
            feedback_parts.append("VLM confirms import workflow")
            
        # Final state verification (10 pts)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
        if final_res and final_res.get("success_indicators") and not final_res.get("error_indicators"):
            vlm_score += 10
            feedback_parts.append("VLM confirms success state")
            
        # Cross-validation (5 pts)
        if (employee_count > 0) and process_res and process_res.get("workflow_completed"):
            vlm_score += 5
            
        score += vlm_score
    else:
        # If no VLM, scale programmatic score to 100
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("VLM unavailable - programmatic score scaled")

    # Pass condition
    passed = score >= 70 and employee_exists and employee_count >= 20

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }