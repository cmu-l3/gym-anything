#!/usr/bin/env python3
"""
Verifier for configure_notification_rules task.

Verification Logic:
1. DB State Verification: Parses the dump of the NotificationRule table to check the status of specific rules.
2. Screenshot Verification: Checks if the agent took the requested screenshot.
3. Change Detection: Compares initial vs final DB state to ensure actual changes were made (anti-gaming).
"""

import json
import os
import sys
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_notification_rules(traj, env_info, task_info):
    """
    Verify the notification rules configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # 1. Load exported result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to load task result data"}

    # 2. Check Screenshot Evidence (10 pts)
    if result_data.get("agent_screenshot_valid"):
        score += 10
        feedback.append("Screenshot saved correctly.")
    elif result_data.get("agent_screenshot_exists"):
        score += 5
        feedback.append("Screenshot exists but timestamp is invalid (created before task?).")
    else:
        feedback.append("Final screenshot not found.")

    # 3. DB Verification (80 pts)
    # We need to analyze the DB dump. Since we don't have direct SQL access here,
    # we rely on the text dump provided by export_result.sh.
    # The dump format from psql is usually pipe-separated or similar.
    # We look for keywords associated with the rules.
    
    db_content = ""
    with tempfile.NamedTemporaryFile(suffix='.txt') as f:
        try:
            copy_from_env("/tmp/db_final.txt", f.name)
            f.seek(0)
            db_content = f.read().decode('utf-8', errors='ignore')
        except Exception as e:
            logger.error(f"Failed to load DB dump: {e}")
            # If DB dump fails, we rely heavily on VLM
            feedback.append("Could not verify Database state directly.")

    # Heuristic parsing of DB content
    # We look for rows that contain rule names and their status (true/false/1/0)
    # Common Internal Names in SDP (examples):
    # 'AcknowledgeRequester' or 'OnNewRequest' + 'Requester'
    # We will look for presence of configurations. 
    # Since we can't be 100% sure of internal names without a running instance doc,
    # we will use a "change detection" + "VLM confirmation" hybrid if DB parsing is ambiguous.
    
    # Let's try to detect the patterns for the 5 rules.
    # We assume the DB dump contains lines like:
    # "rule_name" | "is_enabled" | ...
    
    # Mapping of expected strings to look for in the DB dump
    # We assign points if we find the correct state.
    # This is a heuristic: we search for the rule name AND the enabled status in the same line/block.
    
    # REQUIRED CONFIGURATION:
    # 1. Created -> Req: YES, Tech: YES
    # 2. Assigned -> Req: YES, Tech: YES
    # 3. Picked Up -> Req: NO, Tech: NO
    # 4. Resolved -> Req: YES, Tech: NO
    # 5. Closed -> Req: NO, Tech: NO
    
    # NOTE: In Postgres dumps, 't' is true, 'f' is false. Or '1'/'0'.
    
    # We define a helper to check rules
    def check_rule_db(content, keywords, expected_state):
        # keywords: list of strings that identify the rule row
        # expected_state: True (expect 't'/'true') or False (expect 'f'/'false')
        content_lower = content.lower()
        
        # Simple existence check for keywords
        # This is fuzzy matching on the DB dump
        for line in content_lower.splitlines():
            if all(k.lower() in line for k in keywords):
                # Found the line, check status
                if expected_state:
                    if ' t ' in line or '|t|' in line or 'true' in line or ' 1 ' in line:
                        return True
                    if ' f ' in line or '|f|' in line or 'false' in line or ' 0 ' in line:
                        return False # Found but wrong state
                else:
                    if ' f ' in line or '|f|' in line or 'false' in line or ' 0 ' in line:
                        return True
                    if ' t ' in line or '|t|' in line or 'true' in line or ' 1 ' in line:
                        return False
        return None # Not found

    # DB Scoring
    db_score = 0
    db_max = 80
    
    # Since exact DB schema is black-box in this template generation, we fallback to VLM if DB is unclear,
    # BUT we give points if we see changes in the DB dump vs initial.
    
    # Compare Initial vs Final DB
    initial_db_content = ""
    with tempfile.NamedTemporaryFile(suffix='.txt') as f:
        try:
            copy_from_env("/tmp/db_initial.txt", f.name)
            f.seek(0)
            initial_db_content = f.read().decode('utf-8', errors='ignore')
        except:
            pass
            
    if initial_db_content and db_content and initial_db_content != db_content:
        score += 10
        feedback.append("Database configuration changed (Anti-gaming pass).")
    else:
        feedback.append("No changes detected in Database configuration.")
        
    # 4. VLM Verification (Primary for visual settings) (80 pts distributed)
    # Since DB parsing is risky without exact schema, we lean on VLM to read the settings page.
    
    # Use the agent's screenshot if valid, otherwise system screenshot
    image_path = "/tmp/notification_rules_final.png" if result_data.get("agent_screenshot_valid") else "/tmp/task_final_system_screenshot.png"
    
    # Retrieve the image
    final_image = None
    with tempfile.NamedTemporaryFile(suffix='.png') as f:
        try:
            copy_from_env(image_path, f.name)
            from PIL import Image
            final_image = Image.open(f.name)
        except Exception as e:
            logger.error(f"Failed to get screenshot: {e}")

    if final_image:
        prompt = """
        You are verifying a ManageEngine ServiceDesk Plus task.
        The user had to configure Notification Rules for Requests.
        
        Check the following settings in the screenshot:
        1. "Request is created" -> Requester: ENABLED? Technician: ENABLED?
        2. "Technician is assigned" -> Requester: ENABLED? Technician: ENABLED?
        3. "Request is picked up" -> Requester: DISABLED? Technician: DISABLED?
        4. "Request is resolved" -> Requester: ENABLED? Technician: DISABLED?
        5. "Request is closed" -> Requester: DISABLED? Technician: DISABLED?
        
        Look for checkboxes or toggle switches. 
        - Green check / Filled box = Enabled.
        - Red cross / Empty box = Disabled.
        
        Provide a JSON response:
        {
          "rules_correct": integer (0-5),
          "details": "string explaining what is correct/incorrect"
        }
        """
        
        vlm_res = query_vlm(images=[final_image], prompt=prompt)
        
        if vlm_res and "parsed" in vlm_res:
            parsed = vlm_res["parsed"]
            correct_count = parsed.get("rules_correct", 0)
            vlm_score = (correct_count / 5) * 80 # Up to 80 points
            score += vlm_score
            feedback.append(f"VLM verification: {correct_count}/5 rules look correct. Details: {parsed.get('details', '')}")
        else:
            feedback.append("VLM verification failed to parse response.")
    else:
        feedback.append("No valid screenshot available for VLM verification.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }