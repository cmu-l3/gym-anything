#!/usr/bin/env python3
"""
Verifier for moderate_comments task.

Agent must moderate 7 comments:
1. Approve 3 legitimate authors
2. Mark as Spam (or trash/delete) 4 spam authors
3. Reply to Sarah Mitchell's comment mentioning 'Yoast'
4. Clear the queue

Scoring (100 points):
  - David Chen approved: 10 pts
  - Sarah Mitchell approved: 10 pts
  - Maria Rodriguez approved: 10 pts
  - BestPricesMeds spammed/trashed/deleted: 10 pts
  - SEOExpert2024 spammed/trashed/deleted: 10 pts
  - CryptoKing99 spammed/trashed/deleted: 10 pts
  - FreeGiftCards spammed/trashed/deleted: 10 pts
  - Reply to Sarah containing 'Yoast': 15 pts (8 pts if reply exists but no 'Yoast')
  - Queue completely cleared (0 pending): 5 pts
  - VLM Trajectory / Anti-gaming check: 10 pts

Pass threshold: score >= 70 AND at least 5 of 7 comments correctly moderated.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, images=None):
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

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent moderating a WordPress comment queue.

The agent should:
1. Navigate to the Comments section in the WordPress admin panel.
2. Review the list of pending comments.
3. Click "Approve" on legitimate comments and "Spam" or "Trash" on spam comments.
4. Use the "Reply" feature under a comment from "Sarah Mitchell" to type out a response.

Assess:
1. COMMENTS_SCREEN_VISIBLE: Is the WordPress Comments moderation screen visible in the workflow?
2. ACTIONS_TAKEN: Is there visual evidence of the agent interacting with comments (hover menus visible, bulk actions used, or status messages like "Comment marked as spam")?
3. REPLY_INTERFACE_USED: Is the inline comment reply editor open and being typed in at any point?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes indicating actual work rather than just sitting idle?

Respond in JSON format:
{
    "comments_screen_visible": true/false,
    "actions_taken": true/false,
    "reply_interface_used": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_moderate_comments(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    legit_authors = metadata.get('legitimate_authors', ["David Chen", "Sarah Mitchell", "Maria Rodriguez"])
    spam_authors = metadata.get('spam_authors', ["BestPricesMeds", "SEOExpert2024", "CryptoKing99", "FreeGiftCards"])
    reply_keyword = metadata.get('reply_keyword', "Yoast").lower()

    # Fetch result JSON from the container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/moderate_comments_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh failed."}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}

    comments = result.get('comments', [])
    sarah_id = str(result.get('sarah_comment_id', '0'))
    duration = result.get('task_duration_sec', 0)
    
    score = 0
    feedback_parts = []
    comments_correctly_moderated = 0

    # Helper to find a comment by author name
    def get_comment_by_author(author_name):
        for c in comments:
            if c.get('comment_author', '').lower() == author_name.lower():
                return c
        return None

    # Helper to find children of a specific comment ID
    def get_replies_to(parent_id):
        return [c for c in comments if str(c.get('comment_parent', '')) == str(parent_id)]

    # 1. Check Legitimate Comments (10 pts each)
    for author in legit_authors:
        c = get_comment_by_author(author)
        if c:
            status = str(c.get('comment_approved', ''))
            if status == '1' or status.lower() == 'approved':
                score += 10
                comments_correctly_moderated += 1
                feedback_parts.append(f"{author} approved")
            else:
                feedback_parts.append(f"FAIL: {author} not approved (status: {status})")
        else:
            feedback_parts.append(f"FAIL: {author} comment missing/deleted")

    # 2. Check Spam Comments (10 pts each)
    for author in spam_authors:
        c = get_comment_by_author(author)
        # If the comment doesn't exist anymore, it counts as deleted (which is fine for spam)
        if not c:
            score += 10
            comments_correctly_moderated += 1
            feedback_parts.append(f"{author} deleted")
        else:
            status = str(c.get('comment_approved', '')).lower()
            if status in ['spam', 'trash']:
                score += 10
                comments_correctly_moderated += 1
                feedback_parts.append(f"{author} marked as {status}")
            else:
                feedback_parts.append(f"FAIL: {author} not spam/trashed (status: {status})")

    # 3. Check Reply to Sarah (15 pts)
    replies = get_replies_to(sarah_id)
    if replies:
        # Check if any reply contains the keyword
        has_keyword = False
        for r in replies:
            content = r.get('comment_content', '').lower()
            if reply_keyword in content:
                has_keyword = True
                break
        
        if has_keyword:
            score += 15
            feedback_parts.append("Reply to Sarah contains 'Yoast'")
        else:
            score += 8  # Partial credit
            feedback_parts.append("Reply to Sarah exists but missing 'Yoast'")
    else:
        feedback_parts.append("FAIL: No reply found to Sarah's comment")

    # 4. Check if queue is cleared (0 pending comments) (5 pts)
    pending_count = sum(1 for c in comments if str(c.get('comment_approved', '')) == '0')
    if pending_count == 0:
        score += 5
        feedback_parts.append("Queue cleared")
    else:
        feedback_parts.append(f"FAIL: {pending_count} comments still pending")

    # 5. Trajectory / Anti-gaming check (10 pts)
    # Prefer VLM if available, fallback to basic timing
    query_vlm = env_info.get('query_vlm')
    vlm_passed = False
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            vlm_progression = vlm_res.get("meaningful_progression", False)
            vlm_actions = vlm_res.get("actions_taken", False)
            if vlm_progression and vlm_actions:
                score += 10
                vlm_passed = True
                feedback_parts.append("VLM verified trajectory")
            else:
                feedback_parts.append("VLM check failed workflow verification")
        else:
            # Fallback to duration check if VLM query errors
            if duration >= 10:
                score += 10
                vlm_passed = True
                feedback_parts.append("Anti-gaming check passed (duration > 10s)")
            else:
                feedback_parts.append("FAIL: Task completed suspiciously fast (<10s)")
    else:
        # Fallback to duration check if VLM not supported
        if duration >= 10:
            score += 10
            vlm_passed = True
            feedback_parts.append("Anti-gaming check passed (duration > 10s)")
        else:
            feedback_parts.append("FAIL: Task completed suspiciously fast (<10s)")

    # Final pass/fail logic
    # Threshold: >= 70 points AND at least 5 of 7 comments correctly moderated
    passed = score >= 70 and comments_correctly_moderated >= 5

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "comments_correctly_moderated": comments_correctly_moderated,
            "pending_count": pending_count,
            "vlm_passed": vlm_passed,
            "task_duration_sec": duration
        }
    }