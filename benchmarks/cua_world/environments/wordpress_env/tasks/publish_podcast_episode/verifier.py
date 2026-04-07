#!/usr/bin/env python3
"""
Verifier for Publish Podcast Episode task in WordPress.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (100 points maximum):
  1. "Podcasts" category exists (10 pts)
  2. Media uploaded & correctly titled (15 pts)
  3. Post published with correct title (15 pts)
  4. Post assigned to "Podcasts" category (10 pts)
  5. Show notes paragraph present (10 pts)
  6. Audio block used (15 pts)
  7. Details (accordion) block used with correct summary (15 pts)
  8. Transcript content inserted (10 pts)

VLM checks are used secondarily to verify authentic UI workflow progression if available.

Pass threshold: 75 points, AND MUST include Post published, Audio block, and Details block.
"""

import json
import tempfile
import os
import logging
import re

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, images=None):
    """Run VLM query with multiple trajectory images."""
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

TRAJECTORY_PROMPT = """You are analyzing screenshots from an agent publishing a podcast episode in WordPress.

For successful task completion, the agent should progress through these stages:
1. Navigating to Media Library and uploading an audio file.
2. Creating a new WordPress post.
3. Editing post content using the Gutenberg block editor (adding paragraph, audio player, and details/accordion block).
4. Publishing the post successfully.

Assess:
1. WORKFLOW_COMPLETED: Did the agent interact with both media uploading and post editing?
2. BLOCKS_ADDED: Is there visual evidence of the native audio player or details (accordion) block in the editor?
3. POST_PUBLISHED: Was the post published successfully (e.g., success toast, view post link)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "blocks_added": true/false,
    "post_published": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

def verify_publish_podcast_episode(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/publish_podcast_episode_result.json", temp_result.name)
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

    # Evaluate Programmatic Criteria
    category_id = result.get('category_id', '')
    attachment_id = result.get('attachment_id', '')
    post_id = result.get('post_id', '')
    content = result.get('post_content', '')
    categories = result.get('post_categories', '')

    has_post = False
    has_audio_block = False
    has_details_block = False

    if category_id:
        score += 10
        feedback_parts.append("Category 'Podcasts' exists")
    else:
        feedback_parts.append("Category 'Podcasts' NOT found")

    if attachment_id:
        score += 15
        feedback_parts.append("Media uploaded and correctly titled")
    else:
        feedback_parts.append("Audio attachment with expected title NOT found")

    if post_id:
        score += 15
        has_post = True
        feedback_parts.append("Post published with correct title")
    else:
        feedback_parts.append("Published post with expected title NOT found")

    if categories and ("Podcasts" in categories or "podcasts" in categories.lower()):
        score += 10
        feedback_parts.append("Post assigned to Podcasts category")
    elif post_id:
        feedback_parts.append("Post NOT assigned to Podcasts category")

    content_lower = content.lower()
    if "evolution of cloud infrastructure" in content_lower:
        score += 10
        feedback_parts.append("Show notes present")
    elif post_id:
        feedback_parts.append("Show notes missing")

    if "wp:audio" in content_lower or "class=\"wp-block-audio\"" in content_lower or "[audio" in content_lower:
        score += 15
        has_audio_block = True
        feedback_parts.append("Audio block found")
    elif post_id:
        feedback_parts.append("Audio block missing")

    if "wp:details" in content_lower or "<details" in content_lower:
        has_details_block = True
        if "read episode transcript" in content_lower:
            score += 15
            feedback_parts.append("Details block with correct summary found")
        else:
            score += 5
            feedback_parts.append("Details block found but summary text is missing/wrong")
    elif post_id:
        feedback_parts.append("Details block missing")

    if "manage kubernetes clusters" in content_lower or "serverless scalability" in content_lower:
        score += 10
        feedback_parts.append("Transcript text found")
    elif post_id:
        feedback_parts.append("Transcript text missing")

    # Determine passing based on threshold and mandatory keys
    passed = score >= 75 and has_post and has_audio_block and has_details_block

    # Trajectory-based VLM verification (adds contextual feedback if failed or edge cases)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        if frames and final_frame:
            vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames + [final_frame])
            if vlm_result:
                feedback_parts.append(f"[VLM: workflow={'Completed' if vlm_result.get('workflow_completed') else 'Incomplete'}, blocks_added={'Yes' if vlm_result.get('blocks_added') else 'No'}]")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }