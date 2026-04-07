#!/usr/bin/env python3
"""
Verifier for harden_discussion_pingbacks task.

Verification Strategy:

Programmatic checks (100 points total) — from export script JSON inside container:
  1. Global Pingback Setting (15 pts): default_ping_status = 'closed'
  2. Global Auto-close (15 pts): close_comments_for_old_posts = '1' AND close_comments_days_old = '30'
  3. Global Max Links (10 pts): comment_max_links = '1'
  4. Retroactive Pingback Closure (30 pts): Count of published posts with ping_status='open' is 0
  5. Pingback Spam Removed (15 pts): Pending pingback comments count is 0
  6. Legitimate Comment Preserved (15 pts): Jane Doe's comment is still pending or approved

Pass threshold: 70 points AND the retroactive bulk edit (30 pts) MUST be successfully completed.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def _vlm_query(query_vlm, prompt, images=None):
    """Run VLM query to cross-validate workflow using trajectory frames."""
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring WordPress discussion settings and bulk-editing posts.

Assess:
1. DISCUSSION_SETTINGS_VISITED: Did the agent navigate to Settings > Discussion?
2. POSTS_BULK_EDITED: Did the agent navigate to Posts > All Posts and use the Bulk Edit feature?
3. COMMENTS_MODERATED: Did the agent navigate to the Comments section to manage the queue?

Respond in JSON format:
{
    "discussion_settings_visited": true/false,
    "posts_bulk_edited": true/false,
    "comments_moderated": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_harden_pingbacks(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/harden_pingbacks_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Verification error reading JSON: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {str(e)}"}

    settings = result.get('settings', {})
    posts = result.get('posts', {})
    comments = result.get('comments', {})

    score = 0
    feedback_parts = []
    
    # 1. Global Pingback Setting (15 pts)
    if settings.get('default_ping_status') == 'closed':
        score += 15
        feedback_parts.append("Global pingbacks closed (+15)")
    else:
        feedback_parts.append("Global pingbacks NOT closed")

    # 2. Global Auto-close (15 pts)
    if settings.get('close_comments') == '1' and str(settings.get('close_days')) == '30':
        score += 15
        feedback_parts.append("Auto-close set correctly to 30 days (+15)")
    elif settings.get('close_comments') == '1':
        score += 5
        feedback_parts.append("Auto-close enabled but days incorrect (+5)")
    else:
        feedback_parts.append("Auto-close NOT enabled correctly")

    # 3. Global Max Links (10 pts)
    if str(settings.get('max_links')) == '1':
        score += 10
        feedback_parts.append("Max links set to 1 (+10)")
    else:
        feedback_parts.append("Max links NOT set to 1")

    # 4. Retroactive Pingback Closure (30 pts) - CRITICAL
    open_pings = posts.get('open_pings_count', -1)
    retroactive_passed = False
    if open_pings == 0:
        score += 30
        retroactive_passed = True
        feedback_parts.append("All existing posts retroactively secured (+30)")
    else:
        feedback_parts.append(f"FAILED retroactive secure: {open_pings} posts still vulnerable")

    # 5. Pingback Spam Removed (15 pts)
    pending_pingbacks = comments.get('pending_pingbacks', -1)
    if pending_pingbacks == 0:
        score += 15
        feedback_parts.append("Pingback spam removed (+15)")
    else:
        feedback_parts.append(f"Spam not fully removed: {pending_pingbacks} pending pingbacks remain")

    # 6. Legitimate Comment Preserved (15 pts)
    legit_exists = comments.get('legit_comment_exists', False)
    if legit_exists:
        score += 15
        feedback_parts.append("Legitimate comment preserved (+15)")
    else:
        feedback_parts.append("FAILED to preserve legitimate comment (blind mass deletion)")

    # Optional VLM verification to cross-validate workflow
    query_vlm = env_info.get('query_vlm')
    vlm_result = None
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            if frames and final_frame:
                vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames + [final_frame])
        except Exception as e:
            logger.warning(f"VLM trajectory analysis failed: {e}")

    if vlm_result:
        if vlm_result.get("posts_bulk_edited"):
            feedback_parts.append("[VLM confirmed bulk edit]")
        if vlm_result.get("discussion_settings_visited"):
            feedback_parts.append("[VLM confirmed settings visit]")

    # Pass logic: Must score >= 70 AND successfully perform the bulk edit
    # (Because the bulk edit is the core 'gotcha' of this task)
    passed = (score >= 70) and retroactive_passed

    if not retroactive_passed:
        feedback_parts.append("CRITICAL: Must successfully bulk-edit existing posts to pass.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "score": score,
            "retroactive_passed": retroactive_passed,
            "legit_comment_preserved": legit_exists
        }
    }