#!/usr/bin/env python3
"""
Verifier for add_denied_visitor_watchlist task.

Verification Logic:
1. Primary (Database/Persistence): 
   - Checks if the Lobby Track database file was modified.
   - Parses the 'strings' dump of the binary database to find the specific entered data 
     (Name, Incident ID). This avoids needing specific ODBC drivers for legacy formats.
2. Secondary (VLM): 
   - Uses VLM on the trajectory to confirm the agent navigated to the 'Watchlist' 
     or 'Denied' section and selected the 'Denied' status (visual confirmation).

Scoring:
- 30 pts: Database file modified (work was saved).
- 40 pts: Correct data found in database (Name + Incident ID).
- 30 pts: VLM confirms UI navigation and "Denied" status selection.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_watchlist_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = f"{metadata.get('target_first_name', 'Marcus')} {metadata.get('target_last_name', 'Thornton')}"
    target_incident = metadata.get('target_incident_id', "SI-2024-0341")
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify Database Persistence (30 pts)
    db_modified_path = result.get("db_modified", "")
    if db_modified_path:
        score += 30
        feedback_parts.append("Database persistence verified.")
    else:
        feedback_parts.append("No database changes detected (did you save?).")

    # 3. Verify Data Content via Strings Dump (40 pts)
    # We retrieve the dump of strings from the modified DB
    db_strings_path = result.get("db_strings_path", "")
    content_verified = False
    
    if db_modified_path and db_strings_path:
        local_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(db_strings_path, local_dump.name)
            with open(local_dump.name, 'r', errors='ignore') as f:
                content = f.read()
                
            # Check for Name
            if target_name in content:
                score += 20
                feedback_parts.append(f"Name '{target_name}' found in database.")
            else:
                feedback_parts.append(f"Name '{target_name}' NOT found in database.")

            # Check for Incident ID (Unique identifier)
            if target_incident in content:
                score += 20
                feedback_parts.append(f"Incident ID '{target_incident}' found in database.")
                content_verified = True
            else:
                feedback_parts.append(f"Incident ID '{target_incident}' NOT found in database.")
                
        except Exception as e:
            feedback_parts.append(f"Error reading DB dump: {e}")
        finally:
            if os.path.exists(local_dump.name):
                os.unlink(local_dump.name)
    
    # 4. VLM Verification (30 pts)
    # Necessary to confirm "Denied" status if it's stored as an integer/enum in DB and not visible in strings.
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = (
        "Review these screenshots of a Visitor Management System task.\n"
        "1. Did the user navigate to a 'Watchlist', 'Denied Visitors', or 'Security' list?\n"
        "2. Did the user select 'Denied', 'Banned', or a red icon status for the person 'Marcus Thornton'?\n"
        "3. Is the record visible in a list at the end?\n"
        "Return JSON with keys: 'watchlist_navigated' (bool), 'denied_status_selected' (bool), 'record_visible' (bool)."
    )
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_resp.get("parsed", {})
        
        if parsed.get("watchlist_navigated"):
            vlm_score += 10
        if parsed.get("denied_status_selected"):
            vlm_score += 10
        if parsed.get("record_visible"):
            vlm_score += 10
            
        score += vlm_score
        feedback_parts.append(f"VLM Verification: {vlm_score}/30 points.")
        
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Fallback: if content was perfectly verified in DB, give partial VLM credit
        if content_verified:
            score += 15
            feedback_parts.append("VLM failed, awarded partial credit based on DB success.")

    final_passed = score >= 70
    
    return {
        "passed": final_passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }