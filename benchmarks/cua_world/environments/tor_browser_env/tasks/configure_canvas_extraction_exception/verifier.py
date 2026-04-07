#!/usr/bin/env python3
"""Verifier for configure_canvas_extraction_exception task.

Evaluates whether the agent successfully navigated to a local HTML tool, 
granted a Tor Browser canvas extraction exception, and successfully exported 
the true base64 canvas data to a text file.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_canvas_exception(traj, env_info, task_info):
    """
    Scoring Strategy (100 points):
    1. Output file exists: 20 pts (GATE)
    2. File contains valid base64 and is sufficiently large (> 1000 bytes): 30 pts
    3. Canvas exception recorded in Tor's permissions.sqlite: 30 pts
    4. VLM Trajectory Evidence (Agent interacted with tool/warning): 20 pts

    Pass threshold: 70 points AND (File exists + SQLite Permission granted)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Extract JSON results
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

    logger.info(f"Result Data: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []
    
    # 1. Output File Exists (Gate)
    file_exists = result.get('file_exists', False)
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file /home/ga/Documents/OfflineTools/exported_chart.txt was not created."
        }
    
    score += 20
    feedback_parts.append("Output file exists (20/20)")

    # Anti-gaming: Ensure file is new
    if not result.get('file_is_new', False):
        feedback_parts.append("WARNING: File existed before task start (possible artifact)")
    
    # 2. File Content Valid and Large
    # Tor's blanked canvas is typically < 200 bytes. A real canvas of 800x400 with drawings is > 5000 bytes.
    file_size = result.get('file_size', 0)
    base64_valid = result.get('base64_valid', False)
    content_passed = False
    
    if base64_valid and file_size > 1000:
        score += 30
        content_passed = True
        feedback_parts.append(f"Valid large base64 data extracted ({file_size} bytes) (30/30)")
    elif base64_valid:
        score += 10
        feedback_parts.append(f"Base64 data found but suspiciously small ({file_size} bytes) (10/30)")
    else:
        feedback_parts.append("File content is missing or not a valid data URI (0/30)")

    # 3. Canvas Exception in permissions.sqlite
    perm_granted = result.get('canvas_permission_granted', False)
    if perm_granted:
        score += 30
        feedback_parts.append("Canvas extraction exception found in Tor Browser database (30/30)")
    else:
        feedback_parts.append("Canvas extraction exception NOT found in Tor database (0/30)")

    # 4. VLM Verification (Trajectory checking for tool interaction)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        # SECURITY: Need credentials for LiteLLM/OpenAI
        import openai
        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')
        
        if vlm_api_key and frames:
            client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
            
            # Use base64 encoding
            import base64
            from io import BytesIO
            def encode_img(img):
                img = img.resize((1280, 720))
                buf = BytesIO()
                img.save(buf, format="PNG")
                return base64.b64encode(buf.getvalue()).decode('utf-8')
                
            content_payload = [{"type": "text", "text": "Review these sequential screenshots of a Tor Browser session. Did the user navigate to the 'Offline Investigation Chart Tool' and interact with the 'Export Chart as Base64' button or interact with Tor's address bar icons? Answer YES or NO."}]
            for img in frames + [final_frame]:
                if img:
                    content_payload.append({
                        "type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{encode_img(img)}"}
                    })
            
            response = client.chat.completions.create(
                model='databricks-claude-sonnet-4-5',
                messages=[{"role": "user", "content": content_payload}],
                max_tokens=100,
                temperature=0.0
            )
            
            reply = response.choices[0].message.content.upper()
            if "YES" in reply:
                vlm_score = 20
                feedback_parts.append("VLM verified tool interaction (20/20)")
            else:
                feedback_parts.append("VLM did not detect tool interaction (0/20)")
        else:
            # Automatic credit if VLM is unavailable but programmatic passes strongly
            if content_passed and perm_granted:
                vlm_score = 20
                feedback_parts.append("VLM skipped, programmatic signals strong (20/20)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Give benefit of doubt if DB and file metrics are flawless
        if content_passed and perm_granted:
            vlm_score = 20
            
    score += vlm_score

    # Determine pass/fail
    passed = (score >= 70) and file_exists and perm_granted
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Total Score: {score}/100. Passed: {passed}")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback
    }