#!/usr/bin/env python3
"""Verifier for capture_onion_network_profile task.

An SRE captures a HAR profile of the DuckDuckGo onion service using Tor Browser's Developer Tools.
Verifies the existence of the HAR file, its JSON validity, HAR structure, the presence of the 
target URL inside the profile, and cross-checks with browser history.
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

TASK_NAME = "capture_onion_network_profile"


def verify_vlm_devtools(frames: list) -> dict:
    """
    Use VLM to verify that the Developer Tools (Network tab) were opened during the trajectory.
    This provides anti-gaming against generating fake HAR files purely via scripts.
    """
    try:
        import openai
        
        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')
        
        if not vlm_api_key:
            return {'verified': False, 'details': 'VLM API key missing.'}
            
        client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
        
        content_items = [
            {"type": "text", "text": "Review these screenshots taken during a browser session. Did the user open the Browser Developer Tools, specifically the Network panel? Answer VERIFIED: YES if you see the DevTools panel open on the screen, otherwise VERIFIED: NO. Briefly explain your reasoning."}
        ]
        
        for idx, frame in enumerate(frames):
            buffer = BytesIO()
            # Downsample to save context window while keeping UI recognizable
            img = frame.resize((1280, 720))
            img.save(buffer, format="JPEG")
            img_b64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
            content_items.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{img_b64}"}
            })
            
        messages = [{"role": "user", "content": content_items}]
        
        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=messages,
            max_tokens=200,
            temperature=0.0
        )
        
        resp_text = response.choices[0].message.content
        if isinstance(resp_text, list):
            resp_text = resp_text[-1].get('text', '') if isinstance(resp_text[-1], dict) else str(resp_text[-1])
            
        verified = "VERIFIED: YES" in resp_text.upper()
        return {'verified': verified, 'details': resp_text}
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return {'verified': False, 'details': f"VLM Exception: {e}"}


def verify_capture_onion_network_profile(traj, env_info, task_info):
    """
    Scoring (100 points total):
    1. HAR File exists at the exact path & is newly created    - 20 pts  [REQUIRED GATE]
    2. HAR File is valid JSON and parses correctly             - 20 pts
    3. HAR structure is correct (contains log.entries)         - 20 pts
    4. Target DDG Onion URL is present in the HAR requests     - 20 pts
    5. VLM confirms Network Panel was opened during trajectory - 20 pts

    Browser history is checked as supplementary verification.
    Pass threshold: 60+ points, MUST include passing the file existence gate.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Retrieve the export result metadata
    # ---------------------------------------------------------
    tmp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_meta.close()
    try:
        copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp_meta.name)
        with open(tmp_meta.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read metadata result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Metadata result file not found: {e}"}
    finally:
        if os.path.exists(tmp_meta.name):
            os.unlink(tmp_meta.name)

    logger.info(f"Export Result: {json.dumps(result, indent=2)}")
    
    file_exists = result.get('file_exists', False)
    file_is_new = result.get('file_is_new', False)
    history_ok = result.get('history_has_ddg_onion', False)
    target_onion = task_info.get('metadata', {}).get('target_onion_url', 'duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion')
    
    # Gate 1: File Existence & Timeline
    if file_exists and file_is_new:
        score += 20
        feedback_parts.append("File exists and was created during task (20/20)")
    elif file_exists:
        feedback_parts.append("File exists but was NOT created during task (0/20)")
    else:
        feedback_parts.append("HAR file NOT found (0/20)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # ---------------------------------------------------------
    # Retrieve the actual HAR file and parse it
    # ---------------------------------------------------------
    har_valid_json = False
    har_correct_structure = False
    target_url_found = False
    
    tmp_har = tempfile.NamedTemporaryFile(delete=False, suffix='.har')
    tmp_har.close()
    try:
        copy_from_env("/tmp/exported_profile.har", tmp_har.name)
        with open(tmp_har.name, 'r', encoding='utf-8') as f:
            har_data = json.load(f)
            har_valid_json = True
            
            # Verify structure
            if "log" in har_data and "entries" in har_data["log"]:
                entries = har_data["log"]["entries"]
                if isinstance(entries, list) and len(entries) > 0:
                    har_correct_structure = True
                    
                    # Search for target URL in entries
                    for entry in entries:
                        req_url = entry.get("request", {}).get("url", "")
                        if target_onion in req_url:
                            target_url_found = True
                            break
    except json.JSONDecodeError:
        logger.error("HAR file is not valid JSON")
    except Exception as e:
        logger.error(f"Failed to copy or process HAR file: {e}")
    finally:
        if os.path.exists(tmp_har.name):
            os.unlink(tmp_har.name)
            
    # Score HAR properties
    if har_valid_json:
        score += 20
        feedback_parts.append("HAR file is valid JSON (20/20)")
    else:
        feedback_parts.append("HAR file is NOT valid JSON (0/20)")
        
    if har_correct_structure:
        score += 20
        feedback_parts.append("HAR file has valid 'log.entries' structure (20/20)")
    else:
        feedback_parts.append("HAR file structure invalid or empty (0/20)")
        
    if target_url_found:
        score += 20
        feedback_parts.append("Target DDG Onion URL found in network requests (20/20)")
    else:
        feedback_parts.append("Target URL NOT found in network requests (0/20)")
        
    if not history_ok:
        feedback_parts.append("Warning: Browser history did not confirm onion visit.")
        
    # ---------------------------------------------------------
    # VLM Verification of Trajectory
    # ---------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_res = verify_vlm_devtools(frames)
        if vlm_res.get('verified', False):
            score += 20
            feedback_parts.append("VLM confirmed DevTools Network panel was opened (20/20)")
        else:
            feedback_parts.append("VLM did NOT detect DevTools Network panel (0/20)")
    else:
        feedback_parts.append("No trajectory frames for VLM check (0/20)")

    passed = score >= 60 and file_exists and target_url_found
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "file_exists": 20 if (file_exists and file_is_new) else 0,
            "valid_json": 20 if har_valid_json else 0,
            "har_structure": 20 if har_correct_structure else 0,
            "target_url_found": 20 if target_url_found else 0,
            "vlm_devtools_used": 20 if ('VLM confirmed' in feedback) else 0
        }
    }