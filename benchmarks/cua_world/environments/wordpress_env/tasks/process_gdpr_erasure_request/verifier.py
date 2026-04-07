#!/usr/bin/env python3
"""
Verifier for process_gdpr_erasure_request task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) - from export script JSON inside container:
  1. Export zip exists at exact path (14 pts)
  2. Export zip is valid and contains user's data (14 pts)
  3. User's personal data erased (comments anonymized) (14 pts)
  4. User account deleted (14 pts) - CRITICAL
  5. User's posts preserved and reassigned to admin (14 pts) - CRITICAL

VLM checks (30 points) - using TRAJECTORY frames:
  6. Process verification (15 pts): Frames show agent using WP privacy tools.
  7. Final state verification (10 pts): Final frame confirms task ending nicely.
  8. Cross-validation (5 pts): Programmatic matches VLM workflow.

Pass threshold: 70 points AND user_deleted AND posts_reassigned
(Safely removing the user without destroying company assets is paramount).
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent processing a GDPR data request in WordPress.

The agent should progress through:
1. Navigating to Tools > Export Personal Data
2. Downloading the export file
3. Navigating to Tools > Erase Personal Data
4. Erasing the user's data
5. Navigating to Users and deleting the specific user account
6. Reassigning the user's posts to another user during deletion

Assess:
1. WORKFLOW_COMPLETED: Did the agent use the WordPress privacy tools and delete a user?
2. PRIVACY_TOOLS_USED: Are the "Export Personal Data" or "Erase Personal Data" screens visible?
3. USER_DELETED: Is there evidence of user deletion with content reassignment?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes across different admin pages?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "privacy_tools_used": true/false,
    "user_deleted": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a GDPR request task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface or a terminal visible?
2. SUCCESS_INDICATORS: Are there success messages indicating a user was deleted or data erased?
3. ERROR_INDICATORS: Are there any error messages visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_process_gdpr_erasure_request(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # Load programmatic result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/gdpr_task_result.json", temp_result.name)
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

    # Evaluate Programmatic Criteria (70 points total, 14 points each)
    
    # 1. Export Exists
    if result.get('export_exists', False):
        score += 14
        feedback_parts.append("Export zip exists at correct path")
    else:
        feedback_parts.append("FAIL: Export zip not found at expected path")
        
    # 2. Export Valid
    if result.get('export_valid', False):
        score += 14
        feedback_parts.append("Export zip contains valid user data")
    elif result.get('export_exists', False):
        feedback_parts.append("FAIL: Export zip exists but lacks correct user data")

    # 3. Comments Anonymized
    if result.get('comments_anonymized', False):
        score += 14
        feedback_parts.append("User comments successfully anonymized")
    else:
        feedback_parts.append("FAIL: User comments were not anonymized")

    # 4. User Deleted
    user_deleted = result.get('user_deleted', False)
    if user_deleted:
        score += 14
        feedback_parts.append("Target user account deleted")
    else:
        feedback_parts.append("FAIL: Target user account still exists")

    # 5. Posts Reassigned
    posts_reassigned = result.get('posts_reassigned', False)
    posts_exist = result.get('posts_exist', False)
    
    if posts_reassigned:
        score += 14
        feedback_parts.append("User's posts safely reassigned to admin")
    elif not posts_exist:
        feedback_parts.append("CRITICAL FAIL: User's posts were deleted! Company data lost.")
    else:
        feedback_parts.append("FAIL: User's posts exist but were not reassigned to admin")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Trajectory Check (15 points)
            frames = sample_trajectory_frames(traj, n=4)
            traj_vlm = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            
            if traj_vlm:
                if traj_vlm.get("workflow_completed", False):
                    vlm_score += 5
                if traj_vlm.get("privacy_tools_used", False):
                    vlm_score += 5
                if traj_vlm.get("meaningful_progression", False):
                    vlm_score += 5
                details["vlm_trajectory"] = traj_vlm
                
            # Final State Check (10 points)
            final_frame = get_final_screenshot(traj)
            final_vlm = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            
            if final_vlm:
                if final_vlm.get("admin_visible", False):
                    vlm_score += 5
                if final_vlm.get("success_indicators", False) and not final_vlm.get("error_indicators", False):
                    vlm_score += 5
                details["vlm_final"] = final_vlm
                
            # Cross-validation (5 points)
            if user_deleted and posts_reassigned and traj_vlm and traj_vlm.get("workflow_completed", False):
                vlm_score += 5
                
            score += vlm_score
            feedback_parts.append(f"VLM score: {vlm_score}/30")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification failed, assuming partial credit")
            # If VLM fails, grant partial credit so purely programmatic perfect tasks still pass
            if user_deleted and posts_reassigned and result.get('export_valid', False):
                score += 20 
    else:
        # Scale score if VLM is unavailable
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("VLM unavailable - scaled programmatic score")

    # Critical conditions for passing
    critical_checks_met = user_deleted and posts_reassigned
    passed = score >= 70 and critical_checks_met

    if not critical_checks_met:
        feedback_parts.append("FAILED CRITICAL CHECKS: Must safely delete user AND reassign their posts to admin.")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }