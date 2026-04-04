#!/usr/bin/env python3
"""
Verifier for diagnose_fix_compromised_site task.

Occupation: Web Administrator (SOC 15-1299.01)
Difficulty: Very Hard

The setup script injects 7 issues into the WordPress site. The agent must
discover and fix them all without being told the exact UI path.

Programmatic checks (70 points):
  1. Site title no longer contains spam (10 pts)
  2. Tagline no longer contains spam (10 pts)
  3. Rogue user 'service_worker' deleted (10 pts)
  4. Permalink structure is not plain (10 pts)
  5. Comment moderation enabled (10 pts)
  6. Registration disabled or default role not admin (10 pts)
  7. Timezone restored from UTC (10 pts)

VLM checks (30 points):
  8. Trajectory shows admin panel navigation (15 pts)
  9. Final state shows clean admin (10 pts)
  10. Cross-validation (5 pts)

Pass threshold: score >= 70 AND at least 5 of 7 issues fixed
"""

import json
import tempfile
import os
import logging

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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent investigating and fixing a compromised WordPress site.

The agent should be visiting multiple WordPress admin settings pages to fix security issues:
1. Settings > General (fixing site title, tagline, timezone, registration settings)
2. Settings > Permalinks (restoring clean URL structure)
3. Settings > Discussion (enabling comment moderation)
4. Users (removing unauthorized admin accounts)

Assess:
1. WORKFLOW_COMPLETED: Did the agent visit multiple different settings pages?
2. SETTINGS_MODIFIED: Are there visible changes being made to WordPress settings?
3. USER_MANAGEMENT: Did the agent visit the Users section?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes across different admin pages?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "settings_modified": true/false,
    "user_management": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress site remediation task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. CLEAN_STATE: Does the site title/header look professional (not spammy)?
3. SETTINGS_PAGE: Is a settings page visible showing configured values?
4. ERROR_INDICATORS: Are there any error messages visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "clean_state": true/false,
    "settings_page": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_diagnose_fix_compromised_site(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/diagnose_fix_compromised_site_result.json", temp_result.name)
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

    issues = result.get('issues_fixed', {})
    current = result.get('current_state', {})

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: Site title no longer spam (10 pts)
    title_fixed = issues.get('title_fixed', False)
    if title_fixed:
        score += 10
        feedback_parts.append(f"Site title fixed: '{current.get('blogname', '')}'")
    else:
        feedback_parts.append(f"FAIL: Site title still contains spam: '{current.get('blogname', '')}'")

    # Criterion 2: Tagline no longer spam (10 pts)
    tagline_fixed = issues.get('tagline_fixed', False)
    if tagline_fixed:
        score += 10
        feedback_parts.append(f"Tagline fixed: '{current.get('blogdescription', '')}'")
    else:
        feedback_parts.append(f"FAIL: Tagline still contains spam: '{current.get('blogdescription', '')}'")

    # Criterion 3: Rogue user removed (10 pts)
    rogue_fixed = issues.get('rogue_user_fixed', False)
    if rogue_fixed:
        score += 10
        feedback_parts.append("Rogue user 'service_worker' removed")
    else:
        feedback_parts.append("FAIL: Rogue user 'service_worker' still exists")

    # Criterion 4: Permalink structure not plain (10 pts)
    permalink_fixed = issues.get('permalink_fixed', False)
    if permalink_fixed:
        score += 10
        feedback_parts.append(f"Permalink structure restored: '{current.get('permalink_structure', '')}'")
    else:
        feedback_parts.append("FAIL: Permalink structure still plain (empty)")

    # Criterion 5: Comment moderation enabled (10 pts)
    comment_fixed = issues.get('comment_mod_fixed', False)
    if comment_fixed:
        score += 10
        feedback_parts.append("Comment moderation enabled")
    else:
        feedback_parts.append("FAIL: Comment moderation still disabled")

    # Criterion 6: Registration disabled or default role not admin (10 pts)
    reg_fixed = issues.get('registration_fixed', False)
    if reg_fixed:
        score += 10
        reg_status = current.get('users_can_register', '1')
        role = current.get('default_role', 'administrator')
        feedback_parts.append(f"Registration secured (reg={reg_status}, role={role})")
    else:
        feedback_parts.append(
            f"FAIL: Registration still open as admin "
            f"(reg={current.get('users_can_register')}, role={current.get('default_role')})"
        )

    # Criterion 7: Timezone restored from UTC (10 pts)
    tz_fixed = issues.get('timezone_fixed', False)
    if tz_fixed:
        score += 10
        feedback_parts.append(f"Timezone restored: '{current.get('timezone_string', '')}'")
    else:
        feedback_parts.append(f"FAIL: Timezone still UTC: '{current.get('timezone_string', '')}'")

    fixed_count = issues.get('fixed_count', 0)
    details['fixed_count'] = fixed_count

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False
    vlm_query_failed = False

    sampled_frames = sample_frames(traj, num_samples=12) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                settings_ok = process_result.get('settings_modified', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Full remediation workflow confirmed")
                elif workflow_ok or settings_ok:
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

        if has_final:
            final_result = _vlm_query(
                query_vlm, FINAL_STATE_PROMPT, image=final_frame
            )
            details['vlm_final_state'] = final_result

            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                clean_ok = final_result.get('clean_state', False)
                error_found = final_result.get('error_indicators', False)

                if admin_ok and clean_ok and not error_found:
                    score += 10
                    feedback_parts.append("VLM final: Clean admin state confirmed")
                elif admin_ok and clean_ok:
                    score += 7
                    feedback_parts.append("VLM final: Clean state with warnings")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible but cleanliness unclear")
                else:
                    feedback_parts.append("VLM final: Admin not visible")
            else:
                feedback_parts.append("VLM final check failed")
        else:
            feedback_parts.append("VLM final: No frame")

        if fixed_count >= 5 and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: fixes + VLM workflow agree")
            details['cross_validation'] = 'pass'
        elif fixed_count >= 5 and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation: fixes confirmed but VLM didn't confirm workflow")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and fixed_count < 5:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees workflow but insufficient fixes")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    vlm_required_for_pass = vlm_available and not vlm_query_failed

    if vlm_required_for_pass:
        passed = score >= 70 and fixed_count >= 5 and vlm_workflow_confirmed
    else:
        passed = score >= 70 and fixed_count >= 5

    details.update({
        "title_fixed": title_fixed,
        "tagline_fixed": tagline_fixed,
        "rogue_user_fixed": rogue_fixed,
        "permalink_fixed": permalink_fixed,
        "comment_mod_fixed": comment_fixed,
        "registration_fixed": reg_fixed,
        "timezone_fixed": tz_fixed,
        "fixed_count": fixed_count,
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
