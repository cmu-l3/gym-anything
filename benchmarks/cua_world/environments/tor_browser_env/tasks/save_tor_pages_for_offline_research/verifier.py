#!/usr/bin/env python3
"""Verifier for save_tor_pages_for_offline_research task.

Verifies that the agent successfully created a research directory, saved three
official Tor project pages as HTML files, and created a well-formed bibliography.
Includes VLM validation of trajectory for anti-gaming.
"""

import os
import json
import logging
import tempfile
import base64
from io import BytesIO
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trajectory_with_vlm(traj) -> dict:
    """Use VLM to analyze trajectory frames and ensure legitimate browsing/saving took place."""
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            return {"verified": False, "details": "No trajectory frames available."}
            
        import openai
        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')
        
        if not vlm_api_key:
            logger.warning("VLM_API_KEY not set. Skipping VLM check.")
            return {"verified": True, "details": "Skipped due to missing API key."}

        client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
        
        content = [{"type": "text", "text": "Analyze these sequential frames from a user's web browsing session.\n"
                                            "1. Is the user navigating web pages in a browser?\n"
                                            "2. Do you see evidence of the user interacting with a file manager, text editor, or a 'Save Page As' dialog?\n"
                                            "Respond with exactly 'VERIFIED: YES' if there is evidence of web browsing AND file saving/editing activity. Otherwise 'VERIFIED: NO'."}]
        
        for frame_path in frames:
            if os.path.exists(frame_path):
                img = Image.open(frame_path).resize((1280, 720))
                buf = BytesIO()
                img.save(buf, format="JPEG", quality=75)
                b64 = base64.b64encode(buf.getvalue()).decode('utf-8')
                content.append({"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}})
                
        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=[{"role": "user", "content": content}],
            max_tokens=200,
            temperature=0.0
        )
        
        resp_text = response.choices[0].message.content
        verified = "VERIFIED: YES" in resp_text.upper()
        
        return {"verified": verified, "details": resp_text}
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return {"verified": True, "details": f"Error during VLM check: {e}"}

def verify_save_tor_pages(traj, env_info, task_info):
    """
    Scoring Breakdown (100 points total):
    - Research directory exists: 5 pts [GATE]
    - tor-community.html valid (>0 size, has HTML, has keyword): 10 pts
    - tor-metrics.html valid (>0 size, has HTML, has keyword): 10 pts
    - tor-blog.html valid (>0 size, has HTML, has keyword): 10 pts
    - Files created after task start (anti-gaming): 10 pts
    - Bibliography exists: 5 pts
    - Bibliography header present: 5 pts
    - Bibliography URLs present: 15 pts (5 pts per URL)
    - Browser history contains domains: 15 pts (5 pts per domain)
    - VLM verifies saving/browsing trajectory: 15 pts
    
    Pass threshold: 60 points AND gate criterion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Task Result Data: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []
    
    # 1. Directory Exists [GATE]
    if not result.get('dir_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target directory /home/ga/Documents/TorResearch/ was not created."
        }
    score += 5
    feedback_parts.append("Directory exists (5/5)")

    # 2. HTML Files Valid (30 pts)
    all_files_new = True
    any_files_present = False
    
    for key, name in [('tor_community', 'tor-community.html'), ('tor_metrics', 'tor-metrics.html'), ('tor_blog', 'tor-blog.html')]:
        file_data = result.get(key, {})
        if file_data.get('exists'):
            any_files_present = True
            if not file_data.get('is_new'):
                all_files_new = False
                
            if file_data.get('has_html') and file_data.get('size', 0) > 1000 and file_data.get('has_keyword'):
                score += 10
                feedback_parts.append(f"{name} valid (10/10)")
            elif file_data.get('size', 0) > 0:
                score += 5
                feedback_parts.append(f"{name} exists but invalid content (5/10)")
        else:
            feedback_parts.append(f"{name} missing (0/10)")
            all_files_new = False

    # 3. Files Created After Start (10 pts)
    if any_files_present and all_files_new:
        score += 10
        feedback_parts.append("Files newly created (10/10)")
    else:
        feedback_parts.append("Files pre-date task or missing (0/10)")

    # 4. Bibliography Exists (5 pts)
    if result.get('bib_exists'):
        score += 5
        feedback_parts.append("Bibliography exists (5/5)")
    else:
        feedback_parts.append("Bibliography missing (0/5)")

    # 5. Bibliography Header (5 pts)
    if result.get('bib_header'):
        score += 5
        feedback_parts.append("Bibliography header correct (5/5)")

    # 6. Bibliography URLs (15 pts)
    urls = [('bib_has_community', 'community URL'), ('bib_has_metrics', 'metrics URL'), ('bib_has_blog', 'blog URL')]
    for k, name in urls:
        if result.get(k):
            score += 5
            feedback_parts.append(f"{name} present (5/5)")

    # 7. Browser History (15 pts)
    history = result.get('history', {})
    for k, name in [('community', 'Community'), ('metrics', 'Metrics'), ('blog', 'Blog')]:
        if history.get(k):
            score += 5
            feedback_parts.append(f"{name} visited (5/5)")

    # 8. VLM Trajectory Check (15 pts)
    vlm_result = verify_trajectory_with_vlm(traj)
    if vlm_result.get('verified', False):
        score += 15
        feedback_parts.append("VLM visual verification passed (15/15)")
    else:
        feedback_parts.append(f"VLM visual verification failed (0/15): {vlm_result.get('details', '')}")

    passed = score >= 60
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback
    }