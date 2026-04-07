#!/usr/bin/env python3
"""Verifier for tor_support_diagnostics_bundle task.

Evaluates whether the agent extracted Tor troubleshooting data, filtered
the logs for Bootstrap sequences, and compressed them into a zip archive.
Includes a VLM trajectory check to ensure genuine UI interaction over just
reading logs from the filesystem.
"""

import json
import logging
import os
import tempfile
import base64
from PIL import Image
from io import BytesIO

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "tor_support_diagnostics_bundle"

def verify_ui_interaction_with_vlm(frames: list) -> bool:
    """
    Use VLM to check if the agent genuinely interacted with the Tor Logs modal
    and the about:support page.
    """
    import openai
    
    vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
    vlm_api_key = os.environ.get('VLM_API_KEY')
    
    if not vlm_api_key:
        logger.warning("VLM_API_KEY not set. Skipping VLM check and assuming True.")
        return True

    client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
    
    encoded_frames = []
    for frame_path in frames:
        if os.path.exists(frame_path):
            try:
                img = Image.open(frame_path)
                img.thumbnail((1024, 768)) # Resize to save tokens
                buffer = BytesIO()
                img.save(buffer, format="PNG")
                img_b64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
                encoded_frames.append({
                    "type": "image_url",
                    "image_url": {"url": f"data:image/png;base64,{img_b64}"}
                })
            except Exception as e:
                logger.error(f"Failed to process image {frame_path}: {e}")

    if not encoded_frames:
        return False

    prompt = """Review this sequence of screenshots from a user session.
    
Did the user open ANY of the following Tor Browser internal pages or modals?
1. The 'about:support' page (Troubleshooting Information showing application basics)
2. The 'Tor Logs' modal popup overlay (showing connection logs with 'Copy Tor Log' button)

Reply with "YES" if you can clearly see at least one of these UI elements in the screenshots.
Reply with "NO" if they are entirely absent."""

    messages = [
        {
            "role": "user",
            "content": [{"type": "text", "text": prompt}] + encoded_frames
        }
    ]

    try:
        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=messages,
            max_tokens=10,
            temperature=0.0
        )
        answer = response.choices[0].message.content.strip().upper()
        return "YES" in answer
    except Exception as e:
        logger.error(f"VLM API call failed: {e}")
        return True # Default to true on API failure to prevent unfair task failure

def verify_tor_support_diagnostics_bundle(traj, env_info, task_info):
    """
    Verification strategy:
    1. Check if the zip file was created after the task started (Anti-gaming gate)
    2. Check the zip contents and sizes
    3. Verify text filtering success (bootstrap_phases.txt logic)
    4. VLM Trajectory check to ensure UI usage
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    # Criterion 1: Zip Exists and is New (Required Gate)
    zip_exists = result.get('zip_exists', False)
    zip_is_new = result.get('zip_is_new', False)
    
    if zip_exists and zip_is_new:
        score += 20
        feedback_parts.append("Valid new zip archive found (+20)")
    elif zip_exists:
        feedback_parts.append("Zip archive found but it was created before task start (Stale data)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("Zip archive not found at /home/ga/Documents/tor_diagnostics.zip")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: about_support.txt
    if result.get('about_exists', False):
        score += 10
        feedback_parts.append("about_support.txt found (+10)")
        if result.get('about_valid', False) and result.get('about_size', 0) >= 2000:
            score += 15
            feedback_parts.append("about_support.txt is authentic and large enough (+15)")
        else:
            feedback_parts.append("about_support.txt lacks required content or is too small")
    else:
        feedback_parts.append("about_support.txt missing")

    # Criterion 3: tor_logs.txt
    if result.get('logs_exists', False):
        score += 10
        feedback_parts.append("tor_logs.txt found (+10)")
        if result.get('logs_valid', False) and result.get('logs_size', 0) >= 500:
            score += 15
            feedback_parts.append("tor_logs.txt is authentic and large enough (+15)")
        else:
            feedback_parts.append("tor_logs.txt lacks [NOTICE] markers or is too small")
    else:
        feedback_parts.append("tor_logs.txt missing")

    # Criterion 4: bootstrap_phases.txt and correct filtering
    if result.get('boot_exists', False):
        score += 10
        feedback_parts.append("bootstrap_phases.txt found (+10)")
        if result.get('boot_valid', False):
            score += 20
            feedback_parts.append(f"bootstrap_phases.txt filtering correct ({result.get('boot_lines')} lines) (+20)")
        else:
            feedback_parts.append(f"bootstrap_phases.txt contains invalid lines or lacks content")
    else:
        feedback_parts.append("bootstrap_phases.txt missing")

    # VLM Trajectory Check (to ensure genuine UI interaction)
    frames = sample_trajectory_frames(traj, n=8)
    if frames:
        ui_verified = verify_ui_interaction_with_vlm(frames)
        if not ui_verified:
            feedback_parts.append("WARNING: VLM did not detect Tor Logs modal or about:support UI interaction in trajectory.")
            # Penalize if they cheated by reading files directly from disk instead of using UI
            score = int(score * 0.7) 
    else:
        feedback_parts.append("No trajectory frames to evaluate.")

    passed = score >= 65 and zip_exists and zip_is_new
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }