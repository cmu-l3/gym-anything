#!/usr/bin/env python3
"""
Verifier for import_employees_csv task.

Criteria:
1. Database file modified during task (Anti-gaming)
2. All 5 names found in database (Data integrity)
3. All 5 emails found in database (Mapping correctness)
4. VLM verification of UI state (Secondary)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_employees(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
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

    # Extract metrics
    names_found = result.get("names_found_count", 0)
    emails_found = result.get("emails_found_count", 0)
    db_modified = result.get("db_modified", False)
    total_expected = result.get("total_expected", 5)

    score = 0
    feedback = []

    # Scoring Logic
    
    # 1. Database Modification (10 pts)
    if db_modified:
        score += 10
        feedback.append("Database file updated.")
    else:
        feedback.append("Database file NOT modified.")

    # 2. Names Verification (40 pts)
    # 8 points per name
    name_score = (names_found / total_expected) * 40
    score += name_score
    feedback.append(f"Found {names_found}/{total_expected} names in database.")

    # 3. Emails Verification (30 pts)
    # 6 points per email - verifies that fields were mapped correctly
    email_score = (emails_found / total_expected) * 30
    score += email_score
    feedback.append(f"Found {emails_found}/{total_expected} emails in database.")

    # 4. VLM Verification (20 pts)
    # Check if the UI shows the new employees or if the import dialog was used
    vlm_score = 0
    
    # Sample frames to catch the import process or final list
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    if final_screen:
        frames.append(final_screen)
    
    if frames:
        prompt = """
        Review these screenshots of the Jolly Lobby Track software.
        I am looking for evidence that the user imported or added new employees/hosts.
        
        Look for:
        1. An 'Import' wizard or dialog box.
        2. A list of employees/hosts showing names like 'Alice Intern', 'Bob Intern', 'Evan Intern'.
        3. A 'Success' message after an import operation.
        
        Do you see any of these indicators?
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get("success") and vlm_response.get("parsed", {}).get("answer", False):
                # We assume the VLM wrapper returns a structured bool or we parse the text positive
                # For this simple template, let's assume positive sentiment or keyword match in 'answer'
                # But typically query_vlm returns free text.
                # Let's adjust prompt to request JSON or use a simple heuristic on the text.
                pass
            
            # Simple heuristic since query_vlm format varies: check for positive confirmation words
            text_resp = str(vlm_response).lower()
            if "yes" in text_resp or "visible" in text_resp or "alice" in text_resp:
                vlm_score = 20
                feedback.append("Visual evidence of employee list/import found.")
            else:
                feedback.append("No visual evidence of import in screenshots.")
        except Exception:
            feedback.append("VLM verification failed to run.")
    
    score += vlm_score

    # Final Pass/Fail
    # Must have found at least 4/5 names AND DB modified OR strong VLM evidence
    passed = (names_found >= 4 and db_modified) or (score >= 80)
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " ".join(feedback)
    }