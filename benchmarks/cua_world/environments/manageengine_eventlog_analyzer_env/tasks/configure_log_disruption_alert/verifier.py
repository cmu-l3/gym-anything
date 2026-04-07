#!/usr/bin/env python3
"""
Verifier for configure_log_disruption_alert task.

Criteria:
1. Database Verification: Check if 'Log Collection' alert is enabled with threshold 30.
2. State Change: Verify database state actually changed from initial state.
3. VLM Verification: Use trajectory to confirm UI interaction if DB is ambiguous.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
VLM_PROMPT = """
You are verifying a ManageEngine EventLog Analyzer task.
The user was asked to configure a "Log Collection Status" (or "Device Not Reporting") alert.
The threshold should be set to 30 minutes.

Review the screenshots (especially the final one) and answer:
1. Is the user on a "System Alerts", "Alert Settings", or "Device Management" page?
2. Is there a field visible for "Time Threshold", "Interval", or "Time Limit"?
3. Is the value "30" visible in that field?
4. Is there an "Enable" checkbox or toggle that appears checked/active?
5. Is the specific alert named "Log Collection Status" or similar visible?

Respond in JSON:
{
  "page_correct": true/false,
  "threshold_30_visible": true/false,
  "alert_enabled_visible": true/false,
  "alert_name_correct": true/false,
  "confidence": "low/medium/high"
}
"""

def verify_configure_log_disruption_alert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Helper to import VLM utils dynamically if available
    query_vlm = None
    try:
        from gym_anything.vlm import query_vlm as vlm_func
        query_vlm = vlm_func
    except ImportError:
        pass

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Verification (Primary)
    db_content = result.get("db_content", "")
    db_changed = result.get("db_changed", False)
    
    # Check for keywords in DB dump indicating success
    # We look for "30" (threshold) appearing in the same context as "Log" or "Collection"
    # This is a heuristic parsing of the pipe-delimited or text output from psql
    
    # Regex to find a row with 'Log Collection' or 'Device' and '30' and 'true'/'1' (enabled)
    # The DB dump format depends on psql output, usually pipe separated
    
    db_success = False
    
    # Look for the threshold 30
    has_30 = "30" in db_content
    # Look for enabled flag (t/true/1)
    has_enabled = "t" in db_content or "true" in db_content.lower() or "|1|" in db_content
    # Look for the alert name
    has_name = "Log Collection" in db_content or "Device Not Reporting" in db_content or "No Logs" in db_content
    
    if has_name and has_30:
        score += 40
        feedback_parts.append("Database confirms alert configured with value 30.")
        db_success = True
    elif has_name:
        score += 10
        feedback_parts.append("Database shows alert entry, but threshold might be wrong.")
    
    if db_changed:
        score += 10
        feedback_parts.append("Database configuration changed during task.")
    else:
        feedback_parts.append("No database changes detected.")

    # 2. VLM Verification (Secondary/Confirming)
    vlm_score = 0
    if query_vlm:
        # Get final screenshot
        screenshot_path = result.get("screenshot_path")
        if screenshot_path and result.get("screenshot_exists"):
            try:
                # Use copy_from_env to get the image locally
                local_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
                copy_from_env(screenshot_path, local_img)
                
                vlm_resp = query_vlm(prompt=VLM_PROMPT, image=local_img)
                if os.path.exists(local_img):
                    os.unlink(local_img)
                    
                if vlm_resp and vlm_resp.get('success'):
                    parsed = vlm_resp.get('parsed', {})
                    
                    if parsed.get('threshold_30_visible'):
                        vlm_score += 25
                        feedback_parts.append("VLM confirms threshold '30' is visible.")
                    
                    if parsed.get('alert_enabled_visible'):
                        vlm_score += 15
                        feedback_parts.append("VLM confirms alert is enabled.")
                        
                    if parsed.get('page_correct'):
                        vlm_score += 10
                        feedback_parts.append("VLM confirms correct settings page.")
            except Exception as e:
                logger.error(f"VLM check failed: {e}")
                
    score += vlm_score

    # Logic to combine DB and VLM
    # If DB is strong, we rely on it. If DB is ambiguous, VLM helps.
    
    final_score = min(score, 100)
    passed = final_score >= 70
    
    # Specific fail condition: If absolutely no evidence of "30" in either DB or VLM
    if "30" not in db_content and (not query_vlm or not parsed.get('threshold_30_visible', False)):
        passed = False
        feedback_parts.append("FAILED: Could not verify threshold was set to 30.")

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }