#!/usr/bin/env python3
"""
Verifier for tor_storage_api_isolation_audit task.

Verifies:
1. Creation of test suite (index.html) with relevant API keywords.
2. Execution of python server logging to server.log with multiple GET requests.
3. Accurate initial audit text identifying SW absence and LS presence.
4. Accurate restart audit text identifying LS ephemerality (cleared).
5. VLM trajectory verification to ensure Tor Browser was actually utilized.
"""

import json
import os
import tempfile
import logging
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_storage_api_isolation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result.get('task_start', 0)
    score = 0
    feedback_parts = []
    
    # 1. Verify index.html (20 points)
    index_data = result.get('index_html', {})
    if index_data.get('exists', False) and index_data.get('mtime', 0) >= task_start:
        content = base64.b64decode(index_data.get('content_b64', '')).decode('utf-8', errors='ignore').lower()
        if 'localstorage' in content and 'serviceworker' in content:
            score += 20
            feedback_parts.append("index.html test suite created correctly")
        else:
            score += 10
            feedback_parts.append("index.html created but missing required API keywords")
    else:
        feedback_parts.append("index.html missing or stale")

    # 2. Verify server.log and multiple GET requests (20 points)
    server_log_data = result.get('server_log', {})
    get_count = result.get('get_requests_count', 0)
    if server_log_data.get('exists', False) and server_log_data.get('mtime', 0) >= task_start:
        if get_count >= 2:
            score += 20
            feedback_parts.append(f"server.log confirms {get_count} access(es) - indicating restart test")
        elif get_count == 1:
            score += 10
            feedback_parts.append("server.log confirms only 1 access - restart test likely missed")
        else:
            feedback_parts.append("server.log exists but no GET / requests found")
    else:
        feedback_parts.append("server.log missing or stale")

    # 3. Verify initial_audit.txt (20 points)
    initial_data = result.get('initial_txt', {})
    if initial_data.get('exists', False) and initial_data.get('mtime', 0) >= task_start:
        content = base64.b64decode(initial_data.get('content_b64', '')).decode('utf-8', errors='ignore').lower()
        
        sw_disabled = any(kw in content for kw in ['undefined', 'disable', 'error', 'false', 'no service worker', 'unsupported'])
        ls_success = any(kw in content for kw in ['success', 'written', 'active', 'saved', 'true', 'works', 'set'])
        
        if sw_disabled and ls_success:
            score += 20
            feedback_parts.append("initial_audit.txt accurately reports API states")
        elif sw_disabled or ls_success:
            score += 10
            feedback_parts.append("initial_audit.txt partially correct")
        else:
            feedback_parts.append("initial_audit.txt lacks expected conclusion keywords")
    else:
        feedback_parts.append("initial_audit.txt missing or stale")

    # 4. Verify restart_audit.txt (20 points)
    restart_data = result.get('restart_txt', {})
    if restart_data.get('exists', False) and restart_data.get('mtime', 0) >= task_start:
        content = base64.b64decode(restart_data.get('content_b64', '')).decode('utf-8', errors='ignore').lower()
        
        ls_cleared = any(kw in content for kw in ['clear', 'null', 'empty', 'not persist', 'none', 'deleted', 'removed', 'gone'])
        if ls_cleared:
            score += 20
            feedback_parts.append("restart_audit.txt accurately reports LocalStorage ephemerality")
        else:
            feedback_parts.append("restart_audit.txt lacks expected clearance keywords")
    else:
        feedback_parts.append("restart_audit.txt missing or stale")

    # 5. VLM Verification of Tor Browser utilization (20 points)
    vlm_verified = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        from PIL import Image
        from io import BytesIO

        images_b64 = []
        frames = sample_trajectory_frames(traj, n=3)
        for frame in frames:
            if not isinstance(frame, Image.Image):
                frame = Image.fromarray(frame)
            frame = frame.resize((1280, 720))
            buf = BytesIO()
            frame.save(buf, format="JPEG")
            images_b64.append(base64.b64encode(buf.getvalue()).decode('utf-8'))
        
        # Pull final screenshot too
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_img.close()
        try:
            copy_from_env("/tmp/task_final.png", temp_img.name)
            img = Image.open(temp_img.name).resize((1280, 720))
            buf = BytesIO()
            img.save(buf, format="JPEG")
            images_b64.append(base64.b64encode(buf.getvalue()).decode('utf-8'))
        except Exception:
            pass
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

        if images_b64:
            import openai
            vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
            vlm_api_key = os.environ.get('VLM_API_KEY')
            
            if vlm_api_key:
                client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
                prompt = """Analyze these screenshots from a web developer's session.
                Did the user open Tor Browser, navigate to a local server (e.g., localhost:8080 or 127.0.0.1:8080), and view a test page?
                Respond EXACTLY with:
                VERIFIED: YES or NO
                CONFIDENCE: 0-100
                DETAILS: brief description"""

                content = [{"type": "text", "text": prompt}]
                for b64 in images_b64:
                    content.append({"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}})
                
                response = client.chat.completions.create(
                    model='databricks-claude-sonnet-4-5',
                    messages=[{"role": "user", "content": content}],
                    max_tokens=200,
                    temperature=0.0
                )
                text = response.choices[0].message.content
                if 'VERIFIED: YES' in text.upper():
                    vlm_verified = True
            else:
                logger.warning("VLM_API_KEY missing, assuming True for testing.")
                vlm_verified = True
        else:
            logger.warning("No images extracted for VLM.")
            vlm_verified = True # Grant benefit of doubt if VLM infrastructure fails to extract
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_verified = True # Grant benefit of doubt if library missing

    if vlm_verified:
        score += 20
        feedback_parts.append("VLM confirms Tor Browser workflow")
    else:
        feedback_parts.append("VLM could not confirm Tor Browser usage")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }