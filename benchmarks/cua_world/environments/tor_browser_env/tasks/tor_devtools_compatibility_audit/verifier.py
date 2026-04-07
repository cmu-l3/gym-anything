#!/usr/bin/env python3
"""
Verifier for tor_devtools_compatibility_audit task.

Verifies that the agent correctly audited three sites via Tor Browser using
Developer Tools, constructed the report file, and recorded accurate metrics.
Uses file validation, database history, timestamps, and VLM trajectory tracking.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "tor_devtools_compatibility_audit"

def verify_tor_devtools_compatibility_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Use TemporaryFiles to safely extract data from the container
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_txt.close()
    
    result = {}
    report_content = ""
    
    try:
        # 1. Fetch JSON execution summary
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            with open(tmp_json.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result JSON: {e}")
            
        # 2. Fetch the target output report directly
        try:
            copy_from_env("/home/ga/Documents/tor_compatibility_report.txt", tmp_txt.name)
            with open(tmp_txt.name, 'r', encoding='utf-8') as f:
                report_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read report text: {e}")
            
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
        if os.path.exists(tmp_txt.name):
            os.unlink(tmp_txt.name)

    score = 0
    feedback_parts = []
    
    # Gate Requirement: The file must exist
    file_exists = result.get('file_exists', False)
    if not file_exists or not report_content:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file not found at /home/ga/Documents/tor_compatibility_report.txt (Gate Failed)"
        }
        
    score += 10
    feedback_parts.append("File exists (10/10)")
    
    # Anti-gaming: Ensure file was created during the task
    if result.get('file_is_new', False):
        score += 10
        feedback_parts.append("File is newly created (10/10)")
    else:
        feedback_parts.append("File predates task start (0/10)")
        
    # Validation: Browser history must prove visits to targets
    if result.get('history_check', False):
        score += 10
        feedback_parts.append("History: check.torproject.org (10/10)")
    if result.get('history_download', False):
        score += 10
        feedback_parts.append("History: torproject.org/download (10/10)")
    if result.get('history_eff', False):
        score += 10
        feedback_parts.append("History: eff.org (10/10)")
        
    # File Content Validation
    content_lower = report_content.lower()
    
    if "tor browser compatibility report" in content_lower:
        score += 5
        feedback_parts.append("Header found (5/5)")
        
    urls_found = 0
    if "check.torproject.org" in content_lower: urls_found += 1
    if "torproject.org/download" in content_lower: urls_found += 1
    if "eff.org" in content_lower: urls_found += 1
        
    score += urls_found * 5
    feedback_parts.append(f"URLs mentioned ({urls_found*5}/15)")
    
    if re.search(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', report_content):
        score += 10
        feedback_parts.append("IPv4 found (10/10)")
        
    numbers = [int(n) for n in re.findall(r'\b\d+\b', report_content) if int(n) > 0]
    if len(set(numbers)) >= 3:
        score += 5
        feedback_parts.append("Numeric metrics found (5/5)")
        
    if "tor" in content_lower and ("eff" in content_lower or "electronic frontier" in content_lower):
        score += 5
        feedback_parts.append("Page titles found (5/5)")
        
    if len(report_content) > 200:
        score += 5
        feedback_parts.append("File size > 200B (5/5)")
        
    # VLM Trajectory Verification - Did agent actually open DevTools?
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        all_frames = frames + [final]
        
        messages_content = [{
            "type": "text", 
            "text": "Analyze these screenshots of a web browser session. Did the user open the Developer Tools (specifically the Console tab) at any point? Reply VERIFIED: YES if the DevTools Console is visible, otherwise VERIFIED: NO."
        }]
        
        import base64
        from io import BytesIO
        for frame in all_frames:
            try:
                if hasattr(frame, 'save'): # PIL Image
                    buffer = BytesIO()
                    frame.copy().resize((1280, 720)).save(buffer, format="JPEG")
                    img_str = base64.b64encode(buffer.getvalue()).decode('utf-8')
                elif isinstance(frame, str) and os.path.exists(frame):
                    from PIL import Image
                    buffer = BytesIO()
                    Image.open(frame).resize((1280, 720)).save(buffer, format="JPEG")
                    img_str = base64.b64encode(buffer.getvalue()).decode('utf-8')
                elif hasattr(frame, 'shape'): # Numpy array
                    from PIL import Image
                    buffer = BytesIO()
                    Image.fromarray(frame).resize((1280, 720)).save(buffer, format="JPEG")
                    img_str = base64.b64encode(buffer.getvalue()).decode('utf-8')
                else:
                    continue
                
                messages_content.append({
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{img_str}"}
                })
            except Exception:
                pass
                
        import openai
        vlm_api_key = os.environ.get('VLM_API_KEY')
        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        
        if vlm_api_key:
            client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
            resp = client.chat.completions.create(
                model='databricks-claude-sonnet-4-5',
                messages=[{"role": "user", "content": messages_content}],
                max_tokens=100,
                temperature=0.0
            )
            if 'VERIFIED: YES' in resp.choices[0].message.content.upper():
                vlm_passed = True
    except Exception as e:
        logger.warning(f"VLM trajectory verification skipped/failed: {e}")
        
    if vlm_passed:
        score += 5
        feedback_parts.append("VLM verified DevTools used (5/5)")
    else:
        feedback_parts.append("VLM did not verify DevTools used (0/5)")
        
    passed = score >= 60 and file_exists
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }