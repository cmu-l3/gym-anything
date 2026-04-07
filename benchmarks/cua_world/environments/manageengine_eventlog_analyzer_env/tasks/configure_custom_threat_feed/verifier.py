#!/usr/bin/env python3
"""
Verifier for configure_custom_threat_feed task.

Verification Logic:
1. HTTP Traffic (Primary): Did the SIEM actually fetch the file from our local server?
   - This is the strongest proof of configuration + functionality.
2. Database Config (Secondary): Does the record exist in the DB?
3. VLM (Fallback): If DB/HTTP checks are ambiguous, look at the screen.

Scoring:
- 40 pts: Feed URL configured correctly (Database match OR HTTP hit)
- 30 pts: Feed Name match (Database match)
- 30 pts: Functional Test (HTTP Hit detected)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_threat_feed(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []
    
    # Extract signals
    http_accessed = result.get("feed_accessed_via_http", False)
    db_record_found = result.get("db_record_found", False)
    name_match = result.get("feed_name_match", False)
    url_match = result.get("feed_url_match", False)

    # 1. Functional Verification (Did ELA fetch the feed?)
    # This implies the URL was entered correctly AND the "Update" or "Enable" happened.
    if http_accessed:
        score += 50
        feedback.append("Success: EventLog Analyzer successfully fetched the threat feed (HTTP hit detected).")
        # If HTTP hit happened, the URL *must* be correct, even if DB query failed
        url_match = True 
    else:
        feedback.append("Warning: No HTTP access detected to the threat feed server.")

    # 2. Configuration Verification (Database)
    if db_record_found:
        if name_match:
            score += 20
            feedback.append("Success: Feed name 'Internal_Botnet_Feed' found in configuration.")
        else:
            feedback.append("Partial: Threat configuration found, but name might be incorrect.")
            
        if url_match:
            # If we haven't already awarded points for HTTP access (which implies correct URL), award here
            if not http_accessed:
                score += 30
                feedback.append("Success: Feed URL found in database.")
    else:
        # If DB query failed but HTTP access worked, we assume configuration exists
        if http_accessed:
            score += 20  # Partial credit for config since we saw it work
            feedback.append("Note: Database record not explicitly found, but functionality confirmed via network traffic.")
        else:
            feedback.append("Failure: No threat feed configuration found in database.")

    # 3. VLM Verification (Fallback/Confirmation)
    # If we are missing points, use VLM to verify the UI state
    if score < 100:
        logger.info("Using VLM for verification supplement...")
        final_screenshot = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a ManageEngine EventLog Analyzer task.
        Goal: Add a custom threat feed named 'Internal_Botnet_Feed' with URL 'http://localhost:8888/threats.txt'.
        
        Look at the screenshot. Do you see:
        1. A threat source/feed named 'Internal_Botnet_Feed'?
        2. The URL 'http://localhost:8888/threats.txt' visible?
        3. A status indicating 'Enabled' or 'Success'?
        
        Answer yes/no for each and provide a short summary.
        """
        
        try:
            vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
            if vlm_res.get("success"):
                vlm_text = vlm_res.get("parsed", {}).get("response", "").lower()
                
                if "internal_botnet_feed" in vlm_text or "yes" in vlm_text:
                    score += 10
                    feedback.append("VLM: Confirmed feed presence visually.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Cap score
    score = min(100, score)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }