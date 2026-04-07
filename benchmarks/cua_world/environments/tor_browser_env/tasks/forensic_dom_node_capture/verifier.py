#!/usr/bin/env python3
"""Verifier for forensic_dom_node_capture task.

Verifies that the agent successfully extracted specific DOM nodes using
Tor Browser's Developer Tools, ensuring correct file paths, contents,
and dimensional evidence of node capture (rather than fullscreen screenshots).
Includes VLM-based trajectory verification for Developer Tools usage.
"""

import json
import logging
import os
import tempfile
import base64
from io import BytesIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "forensic_dom_node_capture"


def check_vlm_for_devtools(traj) -> bool:
    """
    Use VLM to analyze trajectory frames to ensure the Developer Tools
    were opened at some point during the task.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames
        # Sample 5 frames across the trajectory to look for DevTools
        frames = sample_trajectory_frames(traj, n=5)
        
        if not frames:
            logger.warning("No trajectory frames available for VLM verification.")
            return False

        # Attempt to import openai for Litellm/VLM call
        import openai
        
        vlm_base_url = os.environ.get('VLM_BASE_URL')
        vlm_api_key = os.environ.get('VLM_API_KEY')

        if not vlm_api_key:
            logger.warning("VLM_API_KEY not set. Skipping VLM trajectory verification.")
            return False

        client = openai.OpenAI(
            base_url=vlm_base_url,
            api_key=vlm_api_key
        )

        content = [{"type": "text", "text": "Review these sequential frames from a web browser session. Did the user open the Developer Tools (Inspector, Network, or Console tab) at any point? Look for the developer tools panel docked at the bottom, right, or in a separate window. Respond with exactly 'YES' or 'NO'."}]
        
        for frame_path in frames:
            if os.path.exists(frame_path):
                from PIL import Image
                img = Image.open(frame_path).resize((1280, 720))
                buf = BytesIO()
                img.save(buf, format="JPEG", quality=80)
                b64 = base64.b64encode(buf.getvalue()).decode('utf-8')
                content.append({
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{b64}"}
                })

        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=[{"role": "user", "content": content}],
            max_tokens=10,
            temperature=0.0
        )
        
        response_text = response.choices[0].message.content.strip().upper()
        logger.info(f"VLM DevTools Check Response: {response_text}")
        return "YES" in response_text

    except Exception as e:
        logger.error(f"VLM trajectory verification failed: {e}")
        return False


def verify_forensic_dom_node_capture(traj, env_info, task_info):
    """
    Scoring (100 points):
    1. Directory exists - 5 pts
    2. Wiki image exists and created during task - 10 pts
    3. Wiki image correct dimensions (Node capture proof) - 15 pts
    4. Status image exists and created during task - 10 pts
    5. Status image correct dimensions (Node capture proof) - 15 pts
    6. Log exists and contains URLs - 10 pts
    7. Browser history verifies visits - 10 pts
    8. VLM Trajectory shows Developer Tools usage - 25 pts

    Pass threshold: 60+ points AND at least one image with correct dimensions (Node capture).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result JSON: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []
    task_start = result.get('task_start_time', 0)

    # Criterion 1: Directory exists (5 pts)
    if result.get('dir_exists', False):
        score += 5
        feedback_parts.append("Directory created (5/5)")
    else:
        feedback_parts.append("Directory not found (0/5)")

    # Criterion 2 & 3: Wiki Infobox image and dimensions
    wiki = result.get('wiki_image', {})
    wiki_node_capture_valid = False
    if wiki.get('exists', False):
        if wiki.get('mtime', 0) >= task_start:
            score += 10
            feedback_parts.append("Wiki image exists (10/10)")
            
            w, h = wiki.get('width', 0), wiki.get('height', 0)
            # Anti-gaming: Not full screen (1920x1080) and within reasonable infobox widths (200-500px)
            if 200 <= w <= 500 and w < 1800 and h < 1000:
                score += 15
                wiki_node_capture_valid = True
                feedback_parts.append(f"Wiki image dimensions {w}x{h} valid for Node Capture (15/15)")
            else:
                feedback_parts.append(f"Wiki image dimensions {w}x{h} invalid for pure Node Capture (0/15)")
        else:
            feedback_parts.append("Wiki image predates task (0/25)")
    else:
        feedback_parts.append("Wiki image missing (0/25)")

    # Criterion 4 & 5: Status block image and dimensions
    status = result.get('status_image', {})
    status_node_capture_valid = False
    if status.get('exists', False):
        if status.get('mtime', 0) >= task_start:
            score += 10
            feedback_parts.append("Status image exists (10/10)")
            
            w, h = status.get('width', 0), status.get('height', 0)
            # Anti-gaming: Not full screen, Status block usually 600-900w, < 800h
            if 0 < w < 1200 and 0 < h < 800:
                score += 15
                status_node_capture_valid = True
                feedback_parts.append(f"Status image dimensions {w}x{h} valid for Node Capture (15/15)")
            else:
                feedback_parts.append(f"Status image dimensions {w}x{h} invalid for pure Node Capture (0/15)")
        else:
            feedback_parts.append("Status image predates task (0/25)")
    else:
        feedback_parts.append("Status image missing (0/25)")

    # Criterion 6: Log exists and contains URLs
    log = result.get('log', {})
    if log.get('exists', False) and log.get('contains_urls', False):
        score += 10
        feedback_parts.append("Capture log valid (10/10)")
    else:
        feedback_parts.append("Capture log invalid or missing (0/10)")

    # Criterion 7: Browser history
    history = result.get('history', {})
    if history.get('visited_wiki', False) and history.get('visited_check', False):
        score += 10
        feedback_parts.append("History confirms visits (10/10)")
    else:
        feedback_parts.append("History missing required visits (0/10)")

    # Criterion 8: VLM Trajectory Check for Developer Tools
    vlm_devtools_used = check_vlm_for_devtools(traj)
    if vlm_devtools_used:
        score += 25
        feedback_parts.append("VLM confirms DevTools usage (25/25)")
    else:
        feedback_parts.append("VLM did not detect DevTools usage (0/25)")

    # Pass threshold: >= 60 AND at least one image successfully captured via Node boundaries
    core_mechanic_proven = wiki_node_capture_valid or status_node_capture_valid
    passed = (score >= 60) and core_mechanic_proven

    if passed:
        feedback = "SUCCESS: " + " | ".join(feedback_parts)
    else:
        feedback = "FAILED: " + " | ".join(feedback_parts)
        if not core_mechanic_proven:
            feedback += " [Critical Failure: Node capture dimensions not met, indicating possible full-screen crop or failure to use Inspector feature]"

    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback
    }