#!/usr/bin/env python3
"""
Verifier for Create Blog Post task in WordPress.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) - from export script JSON inside container:
  1. Post exists in database (10 pts)
  2. Post title matches expected (10 pts)
  3. Post is published (10 pts)
  4. Post has content with required keywords (15 pts)
  5. Category is correct (10 pts)
  6. ALL required tags are assigned (10 pts) - STRICT: must have all tags
  7. Post was newly created (5 pts)

VLM checks (30 points) - using TRAJECTORY frames (framework-captured):
  8. Process verification (15 pts): Sampled trajectory frames show the agent
     navigating WordPress admin, creating a post, and publishing.
  9. Final state verification (10 pts): Final frame shows WordPress admin
     with post created or success message.
  10. Cross-validation (5 pts): Programmatic post found agrees with VLM
      seeing post creation workflow.

Pass threshold: 70 points AND post found AND tags_correct AND content_valid
(when VLM is available, must also have VLM workflow confirmation)
"""

import json
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

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a blog post in WordPress via the admin interface.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful blog post creation, the agent should progress through these stages:
1. WordPress admin dashboard visible (already logged in)
2. Navigation to Posts section (Posts menu, Add New Post page)
3. Post editor being used (title field, content area visible, filling in post details)
4. Category/tags being assigned (category panel, tag input visible)
5. Post published (Publish button clicked, success message, or post visible in post list)

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through at least navigating to the post editor AND entering content?
2. POST_EDITOR_VISIBLE: At any point, is the WordPress post editor visible with fields being filled?
3. PUBLISH_CONFIRMED: Is there evidence the post was published (success message, post list showing new post)?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes (not the same screen repeated)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "post_editor_visible": true/false,
    "publish_confirmed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress blog post creation task.

This is a desktop screenshot showing the WordPress admin interface in a browser.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible (not the login page)?
2. SUCCESS_INDICATORS: Are there any success indicators visible? (e.g., "Post published" message, post visible in list, edit post page showing saved post)
3. POST_DATA_VISIBLE: Can you see any post details (title, content) that were entered?
4. ERROR_INDICATORS: Are there any error messages or warnings visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "post_data_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_create_blog_post(traj, env_info, task_info):
    """
    Verify that the expected blog post was created in WordPress.

    Scoring (100 points total):
    Programmatic (70 pts): post exists (10), title (10), status (10),
                          content with keywords (15), category (10),
                          ALL tags (10), newly created (5)
    VLM (30 pts): trajectory process (15), final state (10), cross-validation (5)

    Pass threshold: 70 points AND post found AND tags correct AND content valid AND
    (VLM confirms workflow OR VLM unavailable)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'The Future of Artificial Intelligence in Healthcare')
    expected_category = metadata.get('expected_category', 'Technology')
    expected_tags = metadata.get('expected_tags', 'AI, healthcare, technology, featured')
    expected_status = metadata.get('expected_status', 'publish')
    min_content_length = metadata.get('min_content_length', 100)
    # Content keywords that MUST be present
    required_content_keywords = metadata.get('required_content_keywords',
        ['diagnostics', 'treatment', 'patient care'])

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Load result file from container
    # ================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_blog_post_result.json", temp_result.name)
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

    initial_count = result.get('initial_post_count', 0)
    current_count = result.get('current_post_count', 0)
    initial_total = result.get('initial_total_count', 0)
    current_total = result.get('current_total_count', 0)
    post_found = result.get('post_found', False)
    post = result.get('post', {})

    logger.info(f"Result: initial={initial_count}, current={current_count}, found={post_found}")
    logger.info(f"Post data: {post}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: Post exists in database (10 points)
    if post_found:
        score += 10
        feedback_parts.append("Post found in database")
    else:
        feedback_parts.append("FAIL: Post NOT found in database")
        if current_total > initial_total:
            feedback_parts.append(f"Note: {current_total - initial_total} new post(s) added but not matching expected")
        else:
            feedback_parts.append("No new posts were added")

    # Criterion 2: Title matches (10 points)
    title = post.get('title', '')
    title_lower = title.strip().lower()
    expected_lower = expected_title.strip().lower()

    title_correct = title_lower == expected_lower
    title_partial = 'artificial intelligence' in title_lower and 'healthcare' in title_lower

    if title_correct:
        score += 10
        feedback_parts.append(f"Title correct: {expected_title}")
    elif title_partial:
        score += 5  # Reduced partial credit
        feedback_parts.append(f"Title partially matches: '{title}'")
    elif title:
        feedback_parts.append(f"FAIL: Title mismatch: expected '{expected_title}', got '{title}'")
    else:
        feedback_parts.append("FAIL: Post title not set")

    # Criterion 3: Post is published (10 points)
    status = post.get('status', '')
    status_correct = status.strip().lower() == expected_status.strip().lower()
    if status_correct:
        score += 10
        feedback_parts.append(f"Post status correct: {expected_status}")
    elif status == 'draft':
        feedback_parts.append("FAIL: Post is in draft status (not published)")
    elif status:
        feedback_parts.append(f"FAIL: Post status mismatch: expected '{expected_status}', got '{status}'")
    else:
        feedback_parts.append("FAIL: Post status not set")

    # Criterion 4: Post has content WITH required keywords (15 points)
    content_length = post.get('content_length', 0)
    content_text = post.get('content', '').lower()  # Need actual content for keyword check

    content_valid = False
    keywords_found = []
    keywords_missing = []

    # Check for required keywords
    for keyword in required_content_keywords:
        if keyword.lower() in content_text:
            keywords_found.append(keyword)
        else:
            keywords_missing.append(keyword)

    if content_length >= min_content_length and len(keywords_missing) == 0:
        score += 15
        content_valid = True
        feedback_parts.append(f"Content valid: {content_length} chars with all required keywords")
    elif content_length >= min_content_length and len(keywords_found) >= 2:
        score += 10
        feedback_parts.append(f"Content partial: {content_length} chars, missing keywords: {keywords_missing}")
    elif content_length >= min_content_length:
        score += 5
        feedback_parts.append(f"FAIL: Content length OK ({content_length} chars) but missing keywords: {keywords_missing}")
    elif content_length > 0:
        feedback_parts.append(f"FAIL: Content too short ({content_length} chars) and missing keywords: {keywords_missing}")
    else:
        feedback_parts.append("FAIL: No content in post")

    # Criterion 5: Category is correct (10 points)
    categories = post.get('categories', '')
    category_correct = False
    if categories:
        cat_list = [c.strip().lower() for c in categories.split(',')]
        if expected_category.strip().lower() in cat_list:
            score += 10
            category_correct = True
            feedback_parts.append(f"Category correct: {expected_category}")
        else:
            feedback_parts.append(f"FAIL: Category mismatch: expected '{expected_category}', got '{categories}'")
    else:
        feedback_parts.append("FAIL: No category assigned")

    # Criterion 6: ALL tags are assigned - STRICT (10 points)
    tags = post.get('tags', '')
    tags_correct = False
    expected_tag_list = [t.strip().lower() for t in expected_tags.split(',')]
    num_required_tags = len(expected_tag_list)

    if tags:
        tag_list = [t.strip().lower() for t in tags.split(',')]
        matching_tags = [t for t in expected_tag_list if t in tag_list]
        missing_tags = [t for t in expected_tag_list if t not in tag_list]

        if len(matching_tags) == num_required_tags:
            score += 10
            tags_correct = True
            feedback_parts.append(f"All {num_required_tags} tags assigned: {tags}")
        else:
            # NO partial credit - must have ALL tags
            feedback_parts.append(f"FAIL: Only {len(matching_tags)}/{num_required_tags} tags assigned. Missing: {missing_tags}")
    else:
        feedback_parts.append(f"FAIL: No tags assigned (required: {expected_tag_list})")

    # Criterion 7: Post was newly created (5 points)
    newly_created = current_total > initial_total
    if newly_created:
        score += 5
        feedback_parts.append("Post count increased (newly created)")
    else:
        feedback_parts.append("Post count unchanged")

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

        # --- VLM Check A: Process Verification - 15 points ---
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                editor_visible = process_result.get('post_editor_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Full workflow progression confirmed")
                elif workflow_ok or editor_visible:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression but workflow unclear")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                vlm_query_failed = True
                feedback_parts.append("VLM process check failed (query error)")
        else:
            feedback_parts.append("VLM process: Insufficient trajectory frames")

        # --- VLM Check B: Final State Verification - 10 points ---
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

        # --- VLM Check C: Cross-validation - 5 points ---
        if post_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: DB post + VLM workflow agree")
            details['cross_validation'] = 'pass'
        elif post_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch: post in DB but workflow not confirmed by VLM")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not post_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees workflow but post not in DB")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        # VLM not available - no free points, just note it
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA - STRICTER
    # ================================================================

    # Must have:
    # 1. score >= 70 (raised from 60)
    # 2. post found
    # 3. title_correct OR title_partial (title must match)
    # 4. tags_correct (ALL tags must be assigned)
    # 5. content_valid (must have required keywords)
    # VLM confirmation is OPTIONAL - only required if VLM successfully processed
    # (If VLM query failed, don't penalize the agent for it)

    title_acceptable = title_correct or title_partial

    # VLM is only required for pass if:
    # 1. VLM is available AND
    # 2. VLM query did NOT fail (returned a result)
    # If VLM query failed, we don't require VLM confirmation
    vlm_required_for_pass = vlm_available and not vlm_query_failed

    if vlm_required_for_pass:
        passed = (score >= 70 and post_found and title_acceptable and
                  tags_correct and content_valid and vlm_workflow_confirmed)
    else:
        passed = score >= 70 and post_found and title_acceptable and tags_correct and content_valid

    details.update({
        "post_found": post_found,
        "title_correct": title_correct,
        "title_partial": title_partial,
        "title_acceptable": title_acceptable,
        "status_correct": status_correct,
        "content_valid": content_valid,
        "content_length": content_length,
        "keywords_found": keywords_found,
        "keywords_missing": keywords_missing,
        "category_correct": category_correct,
        "tags_correct": tags_correct,
        "tags_found": tags.split(',') if tags else [],
        "tags_required": expected_tag_list,
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
