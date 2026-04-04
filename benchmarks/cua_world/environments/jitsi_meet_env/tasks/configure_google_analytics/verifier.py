#!/usr/bin/env python3
"""
Verifier for configure_google_analytics task.

CRITERIA:
1. Configuration file contains the correct Tracking ID (40 pts)
2. Configuration file enables the GA script (30 pts)
3. Config file was modified during task (Anti-gaming) (10 pts)
4. Verification screenshot exists (10 pts)
5. VLM confirms verification screenshot shows console/config evidence (10 pts)
"""

import json
import os
import re
import base64
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_google_analytics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_id = metadata.get('expected_tracking_id', 'UA-88224411-1')
    expected_script = metadata.get('expected_script', 'libs/analytics-ga.min.js')
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Get config content (check both main config and custom config)
    config_content = ""
    config_mtime = 0
    
    # Prefer custom config if it was modified recently, else main config
    if result.get('custom_config_exists') and result.get('custom_config_mtime', 0) > result.get('task_start', 0):
        try:
            config_content = base64.b64decode(result['custom_config_content_b64']).decode('utf-8')
            config_mtime = result['custom_config_mtime']
            feedback_parts.append("Checked custom-config.js")
        except:
            pass
    
    if not config_content and result.get('config_exists'):
        try:
            config_content = base64.b64decode(result['config_content_b64']).decode('utf-8')
            config_mtime = result['config_mtime']
            feedback_parts.append("Checked config.js")
        except:
            pass

    if not config_content:
        return {"passed": False, "score": 0, "feedback": "No configuration file found or readable"}

    # CRITERION 1: Tracking ID (40 pts)
    # Regex to find: googleAnalyticsTrackingId: 'ID' or "ID"
    # Be robust to whitespace and potential comments
    # We want to match active config, so we look for the line NOT starting with //
    
    id_pattern = re.compile(r"^\s*googleAnalyticsTrackingId:\s*['\"]" + re.escape(expected_id) + r"['\"]", re.MULTILINE)
    
    if id_pattern.search(config_content):
        score += 40
        feedback_parts.append("Tracking ID configured correctly")
    else:
        feedback_parts.append(f"Tracking ID {expected_id} not found in active config")

    # CRITERION 2: Script URL (30 pts)
    # Should be in scriptURLs array and NOT commented out
    # Pattern: 'libs/analytics-ga.min.js' inside scriptURLs
    
    # Simple check: is it present and uncommented?
    # This is harder to regex perfectly due to multi-line arrays, so we check if the string exists 
    # and isn't preceded by // on the same line
    script_pattern = re.compile(r"^\s*['\"]" + re.escape(expected_script) + r"['\"]", re.MULTILINE)
    
    if script_pattern.search(config_content):
        score += 30
        feedback_parts.append("Analytics script enabled")
    else:
        # Fallback: check if it's there but maybe inline logic
        if expected_script in config_content and f"// {expected_script}" not in config_content:
            score += 20 # Partial credit if regex failed but string is likely active
            feedback_parts.append("Analytics script found (check formatting)")
        else:
            feedback_parts.append("Analytics script not enabled")

    # CRITERION 3: File modified during task (10 pts)
    task_start = result.get('task_start', 0)
    if config_mtime > task_start:
        score += 10
        feedback_parts.append("Config modified during task")
    else:
        feedback_parts.append("Config NOT modified during task (Anti-gaming)")

    # CRITERION 4: Evidence Screenshot (10 pts)
    evidence_exists = result.get('evidence_exists', False)
    if evidence_exists:
        score += 10
        feedback_parts.append("Evidence screenshot provided")
    
    # CRITERION 5: VLM Check of Evidence (10 pts)
    # Check if the evidence screenshot shows the console or config
    if evidence_exists:
        # We need to pull the evidence file out to pass to VLM
        # The result JSON has the path, but we need to copy the file itself from the container
        evidence_path = result.get('evidence_path')
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(evidence_path, temp_img.name)
            
            prompt = """
            Does this screenshot show a browser developer console or Jitsi Meet configuration settings?
            Look for:
            1. 'googleAnalyticsTrackingId' text
            2. 'UA-88224411-1'
            3. JavaScript console output object/struct
            
            Answer YES or NO.
            """
            
            vlm_res = query_vlm(images=[temp_img.name], prompt=prompt)
            if vlm_res and "YES" in vlm_res.get('result', '').upper():
                score += 10
                feedback_parts.append("VLM confirmed valid evidence")
            else:
                feedback_parts.append("VLM could not confirm evidence validity")
                
        except Exception as e:
            logger.warning(f"Failed to verify evidence screenshot: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }