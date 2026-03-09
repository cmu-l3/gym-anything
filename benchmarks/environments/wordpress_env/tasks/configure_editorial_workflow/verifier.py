#!/usr/bin/env python3
"""
Verifier for configure_editorial_workflow task.

Occupation: Managing Editor / Content Strategist
Difficulty: Very Hard

Agent must create 3 posts with specific authors, categories, scheduling,
and pending review status.

Programmatic checks (70 points):
  1. Post 'Q1 2026 Revenue Analysis' exists (5 pts)
  2. Post 1 author is 'editor' and category is 'News' (10 pts)
  3. Post 1 is scheduled (future) for 2026-03-15 (10 pts)
  4. Post 'Spring Product Launch Preview' exists with author 'author' in 'Technology' (10 pts)
  5. Post 2 is scheduled (future) for 2026-03-20 (10 pts)
  6. Post 'Annual Team Building Event Recap' exists with author 'contributor' in 'Lifestyle' (10 pts)
  7. Post 3 has 'pending' status (15 pts)

VLM checks (30 points):
  8. Trajectory shows post creation/scheduling (15 pts)
  9. Final state (10 pts)
  10. Cross-validation (5 pts)

Pass threshold: score >= 70 AND all 3 posts found
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent setting up editorial content in WordPress.

The agent should:
1. Create multiple new posts
2. Assign different authors to each post
3. Set categories for each post
4. Schedule some posts for future dates
5. Set one post to "Pending Review" status

Assess:
1. WORKFLOW_COMPLETED: Did the agent create posts and configure scheduling/authors?
2. POST_EDITOR_VISIBLE: Are WordPress post creation/editing forms visible?
3. SCHEDULING_VISIBLE: Are date/time scheduling controls visible?
4. MEANINGFUL_PROGRESSION: Do the frames show creating multiple different posts?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "post_editor_visible": true/false,
    "scheduling_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress editorial workflow setup task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. SUCCESS_INDICATORS: Are posts listed or success messages shown?
3. POST_LIST_VISIBLE: Is the posts list showing created posts?
4. ERROR_INDICATORS: Any errors visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "post_list_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def _check_post(post_data, expected_author, expected_category,
                expected_status, expected_date=None):
    """Check a single editorial post. Returns (points_out_of_max, feedback_list)."""
    feedback = []

    if not post_data.get('found', False):
        return 0, ["not found"]

    points = 0

    # Author check
    if post_data.get('author_correct', False):
        points += 1
        feedback.append("author OK")
    else:
        actual = post_data.get('actual_author', '')
        feedback.append(f"author WRONG (got '{actual}', expected '{expected_author}')")

    # Category check
    if post_data.get('category_correct', False):
        points += 1
        feedback.append("category OK")
    else:
        actual = post_data.get('actual_category', '')
        feedback.append(f"category WRONG (got '{actual}', expected '{expected_category}')")

    # Status check
    if post_data.get('status_correct', False):
        points += 1
        feedback.append(f"status OK ({expected_status})")
    else:
        actual = post_data.get('actual_status', '')
        feedback.append(f"status WRONG (got '{actual}', expected '{expected_status}')")

    # Date check (if applicable)
    if expected_date:
        if post_data.get('date_correct', False):
            points += 1
            feedback.append("date OK")
        else:
            actual = post_data.get('actual_date', '')
            feedback.append(f"date WRONG (got '{actual}', expected '{expected_date}')")

    return points, feedback


def verify_configure_editorial_workflow(traj, env_info, task_info):
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
            copy_from_env("/tmp/configure_editorial_workflow_result.json", temp_result.name)
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

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Post 1: Q1 Revenue Analysis
    p1 = posts.get('q1_revenue', {})
    p1_found = p1.get('found', False)

    # Criterion 1: Post 1 exists (5 pts)
    if p1_found:
        score += 5
        feedback_parts.append("Post 'Q1 2026 Revenue Analysis' found")
    else:
        feedback_parts.append("FAIL: Post 'Q1 2026 Revenue Analysis' not found")

    # Criterion 2: Post 1 author+category (10 pts)
    if p1_found:
        p1_pts, p1_fb = _check_post(p1, "editor", "News", "future", "2026-03-15")
        author_cat_ok = p1.get('author_correct', False) and p1.get('category_correct', False)
        if author_cat_ok:
            score += 10
        elif p1.get('author_correct', False) or p1.get('category_correct', False):
            score += 5
        feedback_parts.append(f"Post 1 attrs: {', '.join(p1_fb)}")

    # Criterion 3: Post 1 scheduled for 2026-03-15 (10 pts)
    if p1_found:
        if p1.get('status_correct', False) and p1.get('date_correct', False):
            score += 10
            feedback_parts.append("Post 1 correctly scheduled for 2026-03-15")
        elif p1.get('status_correct', False):
            score += 5
            feedback_parts.append("Post 1 status=future but wrong date")
        elif p1.get('date_correct', False):
            score += 3
            feedback_parts.append("Post 1 correct date but wrong status")
        else:
            feedback_parts.append(f"FAIL: Post 1 not scheduled (status={p1.get('actual_status', '')})")

    # Post 2: Spring Product Launch Preview
    p2 = posts.get('spring_launch', {})
    p2_found = p2.get('found', False)

    # Criterion 4: Post 2 exists with correct author+category (10 pts)
    if p2_found:
        p2_pts, p2_fb = _check_post(p2, "author", "Technology", "future", "2026-03-20")
        author_cat_ok = p2.get('author_correct', False) and p2.get('category_correct', False)
        if author_cat_ok:
            score += 10
        elif p2.get('author_correct', False) or p2.get('category_correct', False):
            score += 5
        feedback_parts.append(f"Post 2 'Spring Product Launch Preview': {', '.join(p2_fb)}")
    else:
        feedback_parts.append("FAIL: Post 'Spring Product Launch Preview' not found")

    # Criterion 5: Post 2 scheduled for 2026-03-20 (10 pts)
    if p2_found:
        if p2.get('status_correct', False) and p2.get('date_correct', False):
            score += 10
            feedback_parts.append("Post 2 correctly scheduled for 2026-03-20")
        elif p2.get('status_correct', False):
            score += 5
            feedback_parts.append("Post 2 status=future but wrong date")
        elif p2.get('date_correct', False):
            score += 3
            feedback_parts.append("Post 2 correct date but wrong status")
        else:
            feedback_parts.append(f"FAIL: Post 2 not scheduled (status={p2.get('actual_status', '')})")

    # Post 3: Annual Team Building Event Recap
    p3 = posts.get('team_building', {})
    p3_found = p3.get('found', False)

    # Criterion 6: Post 3 exists with correct author+category (10 pts)
    if p3_found:
        p3_pts, p3_fb = _check_post(p3, "contributor", "Lifestyle", "pending")
        author_cat_ok = p3.get('author_correct', False) and p3.get('category_correct', False)
        if author_cat_ok:
            score += 10
        elif p3.get('author_correct', False) or p3.get('category_correct', False):
            score += 5
        feedback_parts.append(f"Post 3 'Annual Team Building Event Recap': {', '.join(p3_fb)}")
    else:
        feedback_parts.append("FAIL: Post 'Annual Team Building Event Recap' not found")

    # Criterion 7: Post 3 pending status (15 pts) - higher weight since it's the key differentiator
    if p3_found:
        if p3.get('status_correct', False):
            score += 15
            feedback_parts.append("Post 3 correctly set to 'Pending Review'")
        else:
            actual_status = p3.get('actual_status', '')
            feedback_parts.append(f"FAIL: Post 3 status is '{actual_status}' (expected 'pending')")

    all_found = p1_found and p2_found and p3_found

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
                editor_ok = process_result.get('post_editor_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Editorial workflow confirmed")
                elif workflow_ok or editor_ok:
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

        if all_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: posts + VLM agree")
            details['cross_validation'] = 'pass'
        elif all_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not all_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees work but posts missing")
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
        passed = score >= 70 and all_found and vlm_workflow_confirmed
    else:
        passed = score >= 70 and all_found

    details.update({
        "post_1_found": p1_found,
        "post_2_found": p2_found,
        "post_3_found": p3_found,
        "all_found": all_found,
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
