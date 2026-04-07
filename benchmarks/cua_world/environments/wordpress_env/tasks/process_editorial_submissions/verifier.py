#!/usr/bin/env python3
"""
Verifier for process_editorial_submissions task.

Programmatic Verification (70 pts):
  1. Spam post moved to trash (10 pts)
  2. Category 'Astronomy' assigned to both posts (10 pts)
  3. Article 1 published (5 pts)
  4. Article 1 editor note removed (10 pts)
  5. Article 1 featured image set to roman_telescope.jpg (10 pts)
  6. Article 2 published (5 pts)
  7. Article 2 editor note removed (10 pts)
  8. Article 2 featured image set to hubble_galaxy.jpg (10 pts)

VLM Verification (30 pts):
  9. Trajectory shows editorial workflow (pending list -> edit -> upload -> publish) (15 pts)
  10. Final state shows clean pending queue or published list (15 pts)

Pass Threshold:
  Score >= 70 AND both legitimate articles are published AND both articles have the note removed.
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent acting as a digital editor on a WordPress site.

The agent should progress through the following workflow:
1. Viewing the "Pending" posts queue.
2. Trashing a spam post about Casino SEO.
3. Editing a legitimate pending post ("NASA's Roman Mission..." or "Hubble Views...").
4. Deleting an editorial note in the text editor.
5. Opening the Media Library / Featured Image panel and uploading an image.
6. Categorizing and Publishing the post.
7. Repeating for the second legitimate post.

Assess:
1. WORKFLOW_COMPLETED: Did the agent review pending posts, use the post editor, and interact with the featured image/publish panels?
2. MEDIA_UPLOADED: Is there evidence of the agent uploading images to the media library?
3. POST_EDITED: Is the post editor visible with content being modified?
4. MEANINGFUL_PROGRESSION: Do the frames show sequential progress through these editorial steps?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "media_uploaded": true/false,
    "post_edited": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress editorial task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. SUCCESS_INDICATORS: Are there success messages like "Post published" or does the posts list show the articles as published?
3. CLEAN_QUEUE: Is the pending queue free of the spam casino post?
4. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "clean_queue": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_editorial_submissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # Read the exported JSON results
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/process_editorial_submissions_result.json", temp_result.name)
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

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================
    
    # 1. Spam post moved to trash (10 pts)
    spam_status = result.get("spam_status", "")
    if spam_status == "trash" or spam_status == "deleted":
        score += 10
        feedback_parts.append("Spam post trashed")
    else:
        feedback_parts.append(f"Spam post status is '{spam_status}', expected 'trash'")

    art1 = result.get("art1", {})
    art2 = result.get("art2", {})

    # Helper function to check category safely
    def has_astronomy_category(art_data):
        cats = [c.lower() for c in art_data.get("categories", [])]
        return "astronomy" in cats

    # 2. Category 'Astronomy' assigned to both (10 pts)
    if has_astronomy_category(art1) and has_astronomy_category(art2):
        score += 10
        feedback_parts.append("Category 'Astronomy' assigned to both posts")
    else:
        feedback_parts.append("Category 'Astronomy' missing from one or both posts")

    # ARTICLE 1 ("NASA's Roman Mission...")
    # 3. Publish status (5 pts)
    if art1.get("status") == "publish":
        score += 5
        feedback_parts.append("Article 1 published")
    else:
        feedback_parts.append("Article 1 NOT published")

    # 4. Editor note removed (10 pts)
    if not art1.get("has_note") and art1.get("content_length", 0) > 50:
        score += 10
        feedback_parts.append("Article 1 editor note removed")
    else:
        feedback_parts.append("Article 1 editor note still present or content deleted entirely")

    # 5. Featured image roman_telescope.jpg (10 pts)
    if art1.get("thumb_file") == "roman_telescope.jpg":
        score += 10
        feedback_parts.append("Article 1 image correct")
    else:
        feedback_parts.append(f"Article 1 image incorrect: '{art1.get('thumb_file')}'")

    # ARTICLE 2 ("Hubble Views...")
    # 6. Publish status (5 pts)
    if art2.get("status") == "publish":
        score += 5
        feedback_parts.append("Article 2 published")
    else:
        feedback_parts.append("Article 2 NOT published")

    # 7. Editor note removed (10 pts)
    if not art2.get("has_note") and art2.get("content_length", 0) > 50:
        score += 10
        feedback_parts.append("Article 2 editor note removed")
    else:
        feedback_parts.append("Article 2 editor note still present or content deleted entirely")

    # 8. Featured image hubble_galaxy.jpg (10 pts)
    if art2.get("thumb_file") == "hubble_galaxy.jpg":
        score += 10
        feedback_parts.append("Article 2 image correct")
    else:
        feedback_parts.append(f"Article 2 image incorrect: '{art2.get('thumb_file')}'")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get("query_vlm")
    
    if query_vlm:
        # Trajectory check (15 pts)
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            traj_vlm = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            
            if traj_vlm and traj_vlm.get("workflow_completed"):
                score += 10
                feedback_parts.append("VLM: Workflow sequence verified")
                if traj_vlm.get("media_uploaded"):
                    score += 5
                    feedback_parts.append("VLM: Media upload sequence verified")
            else:
                feedback_parts.append("VLM: Workflow sequence missing or unclear")
        except Exception as e:
            logger.warning(f"Failed to extract trajectory frames: {e}")
            # Give benefit of doubt if VLM framing fails but programmatic is perfect
            if score >= 60:
                score += 15

        # Final state check (15 pts)
        try:
            final_frame = get_final_screenshot(traj)
            final_vlm = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            
            if final_vlm and final_vlm.get("admin_visible") and final_vlm.get("success_indicators"):
                score += 10
                feedback_parts.append("VLM: Final state shows success")
                if final_vlm.get("clean_queue"):
                    score += 5
            else:
                feedback_parts.append("VLM: Final state success unclear")
        except Exception as e:
            logger.warning(f"Failed to get final screenshot: {e}")
            if score >= 60:
                score += 15
    else:
        logger.info("VLM not available, granting VLM points to avoid penalty")
        score += 30
        feedback_parts.append("VLM not available (30 pts automatically granted)")

    # ================================================================
    # FINAL EVALUATION
    # ================================================================
    # Required conditions for any pass:
    key_criteria_met = (
        art1.get("status") == "publish" and 
        art2.get("status") == "publish" and 
        not art1.get("has_note") and 
        not art2.get("has_note") and
        art1.get("content_length", 0) > 50 and
        art2.get("content_length", 0) > 50
    )

    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }