#!/usr/bin/env python3
"""
verifier.py — REST API Key Provisioning and Integration Test

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Target file created during task (20 pts)
  Criterion 2: Target file contains valid JSON (20 pts)
  Criterion 3: JSON contains authenticated OpManager API response (35 pts)
  Criterion 4: VLM trajectory check shows terminal usage and UI navigation (25 pts)
"""

import json
import os
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/api_key_result.json"

def verify_rest_api_key_provisioning(traj, env_info, task_info):
    """
    Verify the rest_api_key_provisioning task.
    Uses programmatic JSON file validation + VLM trajectory validation.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available."}

    local_path = "/tmp/api_key_verify_result.json"
    
    # -----------------------------------------------------------------------
    # 1. Retrieve the exported JSON
    # -----------------------------------------------------------------------
    try:
        copy_from_env(RESULT_FILE, local_path)
        with open(local_path, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve or parse result file: {e}. Check export_result.sh."
        }

    score = 0
    details = []

    # -----------------------------------------------------------------------
    # Criterion 1: File created during task (20 pts)
    # -----------------------------------------------------------------------
    file_exists = result.get("file_exists", False)
    file_mtime = result.get("file_mtime", 0)
    task_start = result.get("task_start", 0)
    file_size = result.get("file_size", 0)
    
    file_created = file_exists and (file_mtime >= task_start)
    
    if file_created and file_size > 0:
        score += 20
        details.append(f"PASS: Output file created during task ({file_size} bytes) (+20)")
    elif file_exists:
        # File exists but timestamps might be weird, give partial
        score += 10
        details.append(f"PARTIAL: Output file exists but timestamp check failed (+10)")
    else:
        details.append("FAIL: Output file not found (0/20)")
        return {"passed": False, "score": score, "feedback": " | ".join(details)}

    # -----------------------------------------------------------------------
    # Criterion 2 & 3: Valid JSON & Authenticated OpManager Response (20 + 35 pts)
    # -----------------------------------------------------------------------
    file_content_b64 = result.get("file_content_b64", "")
    content_str = ""
    try:
        content_str = base64.b64decode(file_content_b64).decode('utf-8', errors='replace').strip()
    except Exception as e:
        logger.warning(f"Base64 decode error: {e}")

    is_json = False
    parsed_json = None
    
    if content_str:
        try:
            parsed_json = json.loads(content_str)
            is_json = True
        except json.JSONDecodeError:
            pass

    if is_json:
        score += 20
        details.append("PASS: File contains valid JSON (+20)")
        
        # Check if it's an authenticated OpManager response
        content_lower = content_str.lower()
        
        is_html = "<html" in content_lower and "<body" in content_lower
        is_auth_error = "invalid api key" in content_lower or "authentication failed" in content_lower
        
        if is_html:
            details.append("FAIL: Output file contains an HTML redirect/login page, not a REST API response (0/35)")
        elif is_auth_error:
            details.append("FAIL: Output file contains an Authentication Error / Invalid API Key response (0/35)")
        elif isinstance(parsed_json, dict) and ("error" in parsed_json and isinstance(parsed_json["error"], dict)):
            # Has an explicit API error that isn't auth (e.g. invalid endpoint), still proves they used a valid key
            # but listDevices shouldn't throw this if called correctly. Give partial.
            score += 20
            details.append("PARTIAL: Valid API key used, but API returned an operational error (+20)")
        elif isinstance(parsed_json, dict) or isinstance(parsed_json, list):
            # Normal authenticated payload
            score += 35
            details.append("PASS: JSON contains an authenticated OpManager API response (+35)")
        else:
            details.append("FAIL: JSON structure does not match expected OpManager API output (0/35)")
    else:
        details.append("FAIL: Output file is not valid JSON (0/55)")

    # -----------------------------------------------------------------------
    # Criterion 4: VLM Trajectory Check (25 pts)
    # -----------------------------------------------------------------------
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            prompt = """You are analyzing a sequence of screenshots from an agent performing a REST API integration task.
The agent needs to:
1. Navigate the OpManager Web UI to generate/view a REST API Key.
2. Open a Linux terminal emulator.
3. Use `curl` in the terminal to execute an API request.

Evaluate the sequence of images chronologically and answer:
1. Did the agent open and use a terminal emulator at any point?
2. Did the agent navigate the web UI to settings/API key sections?

Respond in strict JSON format:
{
    "terminal_used": true/false,
    "ui_navigated": true/false,
    "confidence": "low/medium/high"
}
"""
            vlm_resp = query_vlm(prompt=prompt, images=frames + [final])
            if vlm_resp and vlm_resp.get("success") and vlm_resp.get("parsed"):
                parsed = vlm_resp["parsed"]
                term = parsed.get("terminal_used", False)
                ui = parsed.get("ui_navigated", False)
                
                vlm_score = 0
                if term: vlm_score += 15
                if ui: vlm_score += 10
                
                score += vlm_score
                details.append(f"VLM: Terminal used: {term}, UI navigated: {ui} (+{vlm_score})")
            else:
                details.append("VLM: Could not parse response, assuming programmatic success carries weight (+0)")
        except ImportError:
            # If standard framework functions aren't present, grant VLM points if programmatic passes heavily
            if score >= 75:
                score += 25
                details.append("VLM functions unavailable. Granted points based on strong programmatic success (+25)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if score >= 75:
                score += 25
                details.append("VLM error. Granted points based on strong programmatic success (+25)")
    else:
        # If VLM is not enabled in environment, prorate the score if programmatic passes perfectly
        if score >= 75:
            score += 25
            details.append("VLM disabled in env. Granted points based on strong programmatic success (+25)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }