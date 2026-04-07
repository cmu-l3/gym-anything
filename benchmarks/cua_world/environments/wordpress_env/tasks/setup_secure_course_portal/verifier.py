#!/usr/bin/env python3
"""
Verifier for Setup Secure Course Portal task in WordPress.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (100 points) — from export script JSON:
  1. Parent Page exists (10 pts)
  2. Child Page exists & Hierarchy correct (15 pts)
  3. Password Protection is exactly 'Orbit1969' (20 pts) [CRITICAL]
  4. Comments Disabled (10 pts)
  5. Featured Image set correctly (15 pts)
  6. PDF Content Validation - Uploaded (>500KB) & Linked (30 pts)

VLM checks are used for trajectory validation to ensure no API-only bypasses,
though primarily scored on concrete database states.

Pass threshold: 70 points AND Password must be correct.
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


TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring pages in WordPress.

For this task, the agent should:
1. Create a "History Course Portal" page.
2. Create an "Apollo 11 & 12 Documents" page.
3. Configure settings in the right sidebar (Page Attributes, Visibility/Password, Discussion).
4. Upload images and PDF files to the Media Library.
5. Insert files into the page block editor.

Assess:
1. WORKFLOW_COMPLETED: Did the agent interact with the page editor, upload files, and manipulate the settings sidebar?
2. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""


def verify_setup_secure_course_portal(traj, env_info, task_info):
    """Verify that the secure course portal was created correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_password = metadata.get('expected_password', 'Orbit1969')
    
    score = 0
    feedback_parts = []
    
    # Load JSON Result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_secure_course_portal_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    parent = result.get('parent_page', {})
    child = result.get('child_page', {})
    media = result.get('media', {})

    # 1. Parent Page Exists (10 pts)
    if parent.get('exists', False):
        score += 10
        feedback_parts.append("Parent page created")
    else:
        feedback_parts.append("Parent page missing")

    # 2. Child Page & Hierarchy (15 pts)
    if child.get('exists', False):
        if str(child.get('parent_id', '0')) == str(parent.get('id', '-1')):
            score += 15
            feedback_parts.append("Child page created with correct hierarchy")
        else:
            score += 5
            feedback_parts.append("Child page created but hierarchy incorrect")
    else:
        feedback_parts.append("Child page missing")

    # 3. Password Protection (20 pts) [CRITICAL]
    pwd_correct = False
    if child.get('password') == expected_password:
        pwd_correct = True
        score += 20
        feedback_parts.append("Password correctly set")
    elif child.get('exists', False):
        feedback_parts.append(f"Password missing or incorrect (Found: '{child.get('password')}')")

    # 4. Comments Disabled (10 pts)
    if child.get('exists', False) and child.get('comment_status') == 'closed':
        score += 10
        feedback_parts.append("Comments disabled")
    elif child.get('exists', False):
        feedback_parts.append("Comments not disabled")

    # 5. Featured Image (15 pts)
    if child.get('has_thumbnail', False):
        if 'saturn' in child.get('thumbnail_name', '').lower():
            score += 15
            feedback_parts.append("Saturn V featured image set")
        else:
            score += 5
            feedback_parts.append("Featured image set but incorrect file")
    elif child.get('exists', False):
        feedback_parts.append("No featured image set")

    # 6. PDF Upload & Links (30 pts)
    # Give points for uploading real (large) PDFs and linking them
    large_pdfs = media.get('large_pdfs_count', 0)
    links_exist = child.get('content_links_pdf', False)
    
    if large_pdfs >= 2 and links_exist:
        score += 30
        feedback_parts.append("PDFs uploaded and linked")
    elif large_pdfs >= 2:
        score += 20
        feedback_parts.append("PDFs uploaded but not linked in content")
    elif links_exist:
        score += 10
        feedback_parts.append("Links exist but PDFs were empty/missing (possible fake upload)")
    else:
        feedback_parts.append("PDFs not uploaded or linked")

    # VLM Trajectory Verification (Optional validation)
    query_vlm = env_info.get('query_vlm')
    vlm_confirmed = True
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_result and not vlm_result.get('workflow_completed', False):
            logger.warning("VLM did not detect workflow completion.")
            # We don't deduct points, but we note it.
            feedback_parts.append("VLM visual verification ambiguous")

    passed = score >= 70 and pwd_correct and child.get('exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }