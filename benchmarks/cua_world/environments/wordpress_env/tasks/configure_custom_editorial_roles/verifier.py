#!/usr/bin/env python3
"""
Verifier for Configure Custom Editorial Roles task in WordPress.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON:
  1. Role 'freelance_writer' exists (10 pts)
  2. Role has 'edit_posts' and 'read' capabilities (5 pts)
  3. Role has 'upload_files' capability (10 pts)
  4. Role LACKS 'publish_posts' capability (10 pts) - CRITICAL
  5. Users reassigned to 'freelance_writer' (3 users x 8 pts = 24 pts)
  6. Users NO LONGER have 'author' role (11 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  7. Process verification (15 pts): Frames show agent interacting with role/user management.
  8. Final state verification (10 pts): Final frame shows success or clean admin state.
  9. Cross-validation (5 pts): Programmatic DB results align with VLM visual.

Pass threshold: 70 points AND role exists AND 'upload_files' granted AND 'publish_posts' restricted.
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a custom user role in WordPress.

For successful task completion, the agent typically:
1. Installs a role management plugin (e.g., "User Role Editor" or "Members") OR uses the terminal/WP-CLI.
2. Creates a new role named "Freelance Writer" (slug: freelance_writer).
3. Selects/checks capabilities (like edit_posts, upload_files) and leaves others unchecked (publish_posts).
4. Navigates to Users and edits existing users to assign them the new role.

Assess:
1. WORKFLOW_COMPLETED: Did the agent attempt to configure roles and change user assignments?
2. ROLE_MGMT_VISIBLE: Is a role editor plugin UI visible OR terminal commands for WP-CLI visible?
3. USER_EDITING_VISIBLE: Is the WordPress User list or User editing interface visible?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "role_mgmt_visible": true/false,
    "user_editing_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface or terminal visible?
2. SUCCESS_INDICATORS: Are there success messages (e.g., "Role updated", "Users updated") or does the user list show the new role?
3. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def verify_configure_custom_editorial_roles(traj, env_info, task_info):
    """
    Verify the expected bespoke role was created, capabilities configured, and users reassigned.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_users = metadata.get('target_users', ["sam_taylor", "alex_rivera", "jordan_lee"])
    expected_role_slug = metadata.get('expected_role_slug', "freelance_writer")

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_custom_editorial_roles_result.json", temp_result.name)
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

    role_exists = result.get('role_exists', False)
    caps = result.get('role_capabilities', {})
    user_roles = result.get('user_roles', {})

    # ================================================================
    # PROGRAMMATIC SCORING (Max 70 points)
    # ================================================================
    
    # 1. Role Exists (10 pts)
    if role_exists:
        score += 10
        feedback_parts.append(f"Role '{expected_role_slug}' exists")
    else:
        feedback_parts.append(f"FAIL: Role '{expected_role_slug}' not found")
        # Early exit if the role wasn't even created
        return {
            "passed": False, "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Capabilities Configuration (25 pts)
    # Check edit/read (5 pts)
    has_edit = caps.get('edit_posts', False)
    has_read = caps.get('read', False)
    if has_edit and has_read:
        score += 5
        feedback_parts.append("Has edit/read capabilities")
    else:
        feedback_parts.append("Missing required edit_posts/read capabilities")

    # Check upload_files (10 pts)
    has_upload = caps.get('upload_files', False)
    if has_upload:
        score += 10
        feedback_parts.append("Has upload_files capability")
    else:
        feedback_parts.append("FAIL: Missing upload_files capability")

    # Check publish_posts restriction (10 pts)
    has_publish = caps.get('publish_posts', False)
    if not has_publish:
        score += 10
        feedback_parts.append("Correctly lacks publish_posts capability")
    else:
        feedback_parts.append("FAIL: Dangerously granted publish_posts capability")

    # 3. User Reassignments (35 pts: 24 for reassigning, 11 for clearing old)
    users_reassigned_count = 0
    users_cleaned_count = 0

    for u in target_users:
        u_roles = user_roles.get(u, [])
        if expected_role_slug in u_roles:
            users_reassigned_count += 1
        if "author" not in u_roles:
            users_cleaned_count += 1

    score += (users_reassigned_count * 8)
    if users_reassigned_count == len(target_users):
        feedback_parts.append("All target users reassigned")
    else:
        feedback_parts.append(f"{users_reassigned_count}/{len(target_users)} users reassigned")

    if users_cleaned_count == len(target_users):
        score += 11
        feedback_parts.append("All target users stripped of old 'author' role")
    else:
        # Partial points for clearing some
        score += int((users_cleaned_count / len(target_users)) * 11)
        feedback_parts.append(f"{users_cleaned_count}/{len(target_users)} users stripped of 'author' role")

    # ================================================================
    # VLM SCORING (Max 30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            # Process verification (15 pts)
            proc_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            if proc_result:
                if proc_result.get('workflow_completed', False): vlm_score += 5
                if proc_result.get('role_mgmt_visible', False): vlm_score += 5
                if proc_result.get('user_editing_visible', False): vlm_score += 5
                details['vlm_process'] = proc_result

            # Final state verification (10 pts)
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            if final_result:
                if final_result.get('success_indicators', False): vlm_score += 10
                elif final_result.get('admin_visible', False) and not final_result.get('error_indicators', False):
                    vlm_score += 5
                details['vlm_final'] = final_result
                
            # Cross-validation (5 pts)
            if vlm_score >= 10 and role_exists and users_reassigned_count > 0:
                vlm_score += 5
                
            score += vlm_score
            feedback_parts.append(f"VLM verification passed ({vlm_score}/30 pts)")
        except Exception as e:
            logger.warning(f"VLM evaluation failed: {e}")
            # Grant proportional points if VLM fails but programmatic is perfect
            if score == 70:
                score += 30
                feedback_parts.append("VLM error - granted points based on perfect programmatic state")
    else:
        # Scale score to 100 if VLM is completely unavailable
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("VLM unavailable - programmatic score scaled")

    # ================================================================
    # FINAL EVALUATION
    # ================================================================
    score = min(100, max(0, score))
    
    # Must explicitly meet the security constraints to pass
    critical_success = (
        role_exists and 
        has_upload and 
        not has_publish and 
        users_reassigned_count == len(target_users)
    )

    passed = score >= 70 and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }