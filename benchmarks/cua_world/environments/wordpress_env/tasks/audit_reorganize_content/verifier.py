#!/usr/bin/env python3
"""
Verifier for audit_reorganize_content task.

Occupation: Archivist (SOC 25-4011.00) / Content Strategist
Difficulty: Very Hard

Agent must fix miscategorized posts, delete spam, publish drafts,
and add tags across multiple posts.

Programmatic checks (70 points):
  1. 'Cloud Computing Trends 2026' in Technology + published (10 pts)
  2. 'AI in Software Development' in Technology (10 pts)
  3. 'Weekend Hiking Trail Guide' in Lifestyle (10 pts)
  4. 'Healthy Meal Prep Ideas' in Lifestyle (10 pts)
  5. 'Breaking: Local Business Awards Announced' in News + published (10 pts)
  6. Spam post deleted/trashed (10 pts)
  7. 'featured' tag on all 5 legitimate posts (10 pts)

VLM checks (30 points):
  8. Trajectory shows post editing workflow (15 pts)
  9. Final state (10 pts)
  10. Cross-validation (5 pts)

Pass threshold: score >= 70 AND spam deleted AND at least 4 of 5 posts recategorized
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent reorganizing content in WordPress.

The agent should:
1. Navigate to the Posts list in WordPress admin
2. Edit multiple posts to change their categories
3. Delete a spam post
4. Publish draft posts
5. Add tags to posts

Assess:
1. WORKFLOW_COMPLETED: Did the agent edit multiple posts and change categories?
2. POST_EDITING: Are post editing forms visible with category/tag changes?
3. BULK_OPERATIONS: Is the agent performing changes across multiple posts?
4. MEANINGFUL_PROGRESSION: Do the frames show real changes across different posts?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "post_editing": true/false,
    "bulk_operations": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress content reorganization task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. SUCCESS_INDICATORS: Are posts shown with updated categories or success messages?
3. ORGANIZED_CONTENT: Does the post list show organized content?
4. ERROR_INDICATORS: Any errors visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "organized_content": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_audit_reorganize_content(traj, env_info, task_info):
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
            copy_from_env("/tmp/audit_reorganize_content_result.json", temp_result.name)
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

    posts = result.get('posts', {})
    recategorized_count = 0

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: Cloud Computing in Technology + published (10 pts)
    p1 = posts.get('cloud_computing', {})
    if p1.get('category_correct', False) and p1.get('status_correct', False):
        score += 10
        recategorized_count += 1
        feedback_parts.append("'Cloud Computing Trends 2026' → Technology + published")
    elif p1.get('category_correct', False):
        score += 7
        recategorized_count += 1
        feedback_parts.append("'Cloud Computing Trends 2026' → Technology (but not published)")
    elif p1.get('found', False):
        feedback_parts.append(
            f"FAIL: 'Cloud Computing' cat={p1.get('actual_category', '?')}, "
            f"status={p1.get('actual_status', '?')}"
        )
    else:
        feedback_parts.append("FAIL: 'Cloud Computing Trends 2026' not found")

    # Criterion 2: AI in Development in Technology (10 pts)
    p2 = posts.get('ai_development', {})
    if p2.get('category_correct', False):
        score += 10
        recategorized_count += 1
        feedback_parts.append("'AI in Software Development' → Technology")
    elif p2.get('found', False):
        feedback_parts.append(
            f"FAIL: 'AI in Software Development' cat={p2.get('actual_category', '?')}"
        )
    else:
        feedback_parts.append("FAIL: 'AI in Software Development' not found")

    # Criterion 3: Hiking Guide in Lifestyle (10 pts)
    p3 = posts.get('hiking_guide', {})
    if p3.get('category_correct', False):
        score += 10
        recategorized_count += 1
        feedback_parts.append("'Weekend Hiking Trail Guide' → Lifestyle")
    elif p3.get('found', False):
        feedback_parts.append(
            f"FAIL: 'Weekend Hiking Trail Guide' cat={p3.get('actual_category', '?')}"
        )
    else:
        feedback_parts.append("FAIL: 'Weekend Hiking Trail Guide' not found")

    # Criterion 4: Meal Prep in Lifestyle (10 pts)
    p4 = posts.get('meal_prep', {})
    if p4.get('category_correct', False):
        score += 10
        recategorized_count += 1
        feedback_parts.append("'Healthy Meal Prep Ideas' → Lifestyle")
    elif p4.get('found', False):
        feedback_parts.append(
            f"FAIL: 'Healthy Meal Prep Ideas' cat={p4.get('actual_category', '?')}"
        )
    else:
        feedback_parts.append("FAIL: 'Healthy Meal Prep Ideas' not found")

    # Criterion 5: Business Awards in News + published (10 pts)
    p5 = posts.get('business_awards', {})
    if p5.get('category_correct', False) and p5.get('status_correct', False):
        score += 10
        recategorized_count += 1
        feedback_parts.append("'Breaking: Local Business Awards' → News + published")
    elif p5.get('category_correct', False):
        score += 7
        recategorized_count += 1
        feedback_parts.append("'Breaking: Local Business Awards' → News (but not published)")
    elif p5.get('found', False):
        feedback_parts.append(
            f"FAIL: 'Business Awards' cat={p5.get('actual_category', '?')}, "
            f"status={p5.get('actual_status', '?')}"
        )
    else:
        feedback_parts.append("FAIL: 'Breaking: Local Business Awards' not found")

    # Criterion 6: Spam deleted (10 pts)
    spam_deleted = result.get('spam_deleted', False)
    if spam_deleted:
        score += 10
        feedback_parts.append("Spam post deleted/trashed")
    else:
        feedback_parts.append("FAIL: Spam post still exists")

    # Criterion 7: 'featured' tag on all 5 legitimate posts (10 pts)
    tagged_count = 0
    for key in ['cloud_computing', 'ai_development', 'hiking_guide', 'meal_prep', 'business_awards']:
        p = posts.get(key, {})
        if p.get('has_tag', False):
            tagged_count += 1

    if tagged_count == 5:
        score += 10
        feedback_parts.append("All 5 posts tagged 'featured'")
    elif tagged_count >= 3:
        score += 5
        feedback_parts.append(f"{tagged_count}/5 posts tagged 'featured'")
    elif tagged_count > 0:
        score += 2
        feedback_parts.append(f"Only {tagged_count}/5 posts tagged 'featured'")
    else:
        feedback_parts.append("FAIL: No posts tagged 'featured'")

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
                editing_ok = process_result.get('post_editing', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Content audit workflow confirmed")
                elif workflow_ok or editing_ok:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                vlm_query_failed = True
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

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
                    feedback_parts.append("VLM final: Organized content confirmed")
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

        if recategorized_count >= 4 and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: recategorization + VLM agree")
            details['cross_validation'] = 'pass'
        elif recategorized_count >= 4 and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and recategorized_count < 4:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees work but insufficient fixes")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'
    else:
        feedback_parts.append("VLM checks skipped")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    vlm_required_for_pass = vlm_available and not vlm_query_failed

    if vlm_required_for_pass:
        passed = (score >= 70 and spam_deleted and
                  recategorized_count >= 4 and vlm_workflow_confirmed)
    else:
        passed = score >= 70 and spam_deleted and recategorized_count >= 4

    details.update({
        "recategorized_count": recategorized_count,
        "spam_deleted": spam_deleted,
        "tagged_count": tagged_count,
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
