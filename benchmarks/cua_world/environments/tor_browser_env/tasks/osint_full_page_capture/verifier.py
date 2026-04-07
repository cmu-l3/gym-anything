#!/usr/bin/env python3
"""Verifier for osint_full_page_capture task.

Verifies that the agent successfully navigated to specific pages, captured
a full-page continuous screenshot, a standard viewport screenshot, and logged the URLs.

Includes programmatic height checks and trajectory VLM verification.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trajectory_with_vlm(traj) -> dict:
    """
    Use VLM on trajectory frames to verify the agent actually interacted with Tor Browser
    and navigated the pages, rather than just running a python script to download images.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        import openai
        import base64
        from io import BytesIO

        # Sample frames from the trajectory
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if not images:
            return {"score": 0, "feedback": "No trajectory frames available for VLM."}

        # Encode images
        base64_images = []
        for img in images:
            if img:
                # Assuming img is a PIL Image based on the framework implementation
                if hasattr(img, 'save'):
                    buffer = BytesIO()
                    img.save(buffer, format="JPEG")
                    base64_images.append(base64.b64encode(buffer.getvalue()).decode('utf-8'))

        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')

        if not vlm_api_key:
            logger.warning("VLM_API_KEY not set in environment, VLM verification skipped.")
            return {"score": 25, "feedback": "VLM Verification skipped (No API Key). Full points awarded provisionally."}

        client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)

        prompt = """Analyze these trajectory frames from a web browsing session.
Did the user interact with the Tor Browser UI to navigate to community.torproject.org and check.torproject.org?
Look for evidence of the Developer Tools (Web Console) being opened or the `:screenshot` command being typed.

Respond EXACTLY with:
VERIFIED: [YES/NO]
DETAILS: [Brief reasoning]"""

        content = [{"type": "text", "text": prompt}]
        for b64 in base64_images:
            content.append({"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}})

        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=[{"role": "user", "content": content}],
            max_tokens=200,
            temperature=0.0
        )
        
        response_text = response.choices[0].message.content
        if "VERIFIED: YES" in response_text.upper():
            return {"score": 25, "feedback": "VLM Confirmed interaction with Tor Browser & DevTools (25/25)"}
        else:
            return {"score": 5, "feedback": f"VLM could not confirm interaction. Details: {response_text}"}

    except ImportError:
        logger.warning("gym_anything.vlm not available. Skipping VLM check.")
        return {"score": 25, "feedback": "VLM Verification skipped (Missing gym_anything). Full points awarded provisionally."}
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return {"score": 25, "feedback": f"VLM Verification skipped due to error: {e}"}


def verify_osint_capture(traj, env_info, task_info):
    """
    Scoring (100 points total):
    1. Directory created                 - 10 pts
    2. Sites in Tor history              - 15 pts
    3. Capture log exists & valid        - 15 pts
    4. Viewport PNG exists & height <= 1200 - 15 pts
    5. Full page PNG exists & height >= 2000 - 20 pts (GATE)
    6. VLM Trajectory Verification       - 25 pts

    Pass threshold: 70+ points AND Full-page PNG criteria met (Gate).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_full_height = metadata.get('min_full_height', 2000)
    max_viewport_height = metadata.get('max_viewport_height', 1200)

    # 1. Fetch JSON result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result metrics: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []
    task_start_ts = result.get('task_start_ts', 0)

    # 1. Directory created
    if result.get('dir_exists'):
        score += 10
        feedback_parts.append("Evidence Directory created (10/10)")
    else:
        feedback_parts.append("Evidence Directory NOT created (0/10)")

    # 2. History verification
    hist_community = result.get('history_community_torproject', False)
    hist_check = result.get('history_check_torproject', False)
    if hist_community and hist_check:
        score += 15
        feedback_parts.append("Both URLs found in Tor history (15/15)")
    elif hist_community or hist_check:
        score += 7
        feedback_parts.append("Only one URL found in Tor history (7/15)")
    else:
        feedback_parts.append("No required URLs found in Tor history (0/15)")

    # 3. Log file verification
    if result.get('log_exists'):
        log_content = result.get('log_content', '').lower()
        if "community.torproject.org" in log_content and "check.torproject.org" in log_content:
            score += 15
            feedback_parts.append("Log file contains both URLs (15/15)")
        else:
            score += 5
            feedback_parts.append("Log file exists but missing target URLs (5/15)")
    else:
        feedback_parts.append("Log file NOT found (0/15)")

    # 4. Viewport PNG verification
    viewport_exists = result.get('viewport_png_exists', False)
    viewport_height = result.get('viewport_png_height', 0)
    viewport_mtime = result.get('viewport_png_mtime', 0)

    if viewport_exists and viewport_mtime >= task_start_ts:
        if 0 < viewport_height <= max_viewport_height:
            score += 15
            feedback_parts.append(f"Viewport capture valid (height: {viewport_height}px) (15/15)")
        else:
            score += 5
            feedback_parts.append(f"Viewport capture invalid height (height: {viewport_height}px) (5/15)")
    else:
        feedback_parts.append("Viewport capture missing or stale (0/15)")

    # 5. Full page PNG verification (GATE)
    full_exists = result.get('full_png_exists', False)
    full_height = result.get('full_png_height', 0)
    full_mtime = result.get('full_png_mtime', 0)
    full_page_gate_passed = False

    if full_exists and full_mtime >= task_start_ts:
        if full_height >= min_full_height:
            score += 20
            full_page_gate_passed = True
            feedback_parts.append(f"Full-page capture valid (height: {full_height}px) (20/20)")
        else:
            feedback_parts.append(f"Full-page capture failed height threshold ({full_height}px < {min_full_height}px) (0/20)")
    else:
        feedback_parts.append("Full-page capture missing or stale (0/20)")

    # 6. VLM Trajectory Verification
    vlm_result = verify_trajectory_with_vlm(traj)
    score += vlm_result['score']
    feedback_parts.append(vlm_result['feedback'])

    # Final Evaluation
    passed = (score >= 70) and full_page_gate_passed

    feedback = " | ".join(feedback_parts)
    logger.info(f"Final Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback
    }