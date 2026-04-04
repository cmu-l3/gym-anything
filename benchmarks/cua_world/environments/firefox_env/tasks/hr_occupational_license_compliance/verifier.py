#!/usr/bin/env python3
"""
Verifier for hr_occupational_license_compliance task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hr_license_compliance(traj, env_info, task_info):
    """
    Verifies the HR License Compliance task.
    
    Scoring Breakdown (100 pts):
    1. History Evidence (15 pts): Visited careeronestop.org.
    2. Bookmarks (30 pts): 'State Boards' folder exists (15) with >=3 bookmarks (15).
    3. Report Existence & Freshness (15 pts): File exists and created during task.
    4. Report Content (40 pts):
       - Structure (10): Keys for arizona, maryland, washington.
       - Data Accuracy (30): 10 pts per state for correct authority/renewal keywords.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata for ground truth
    metadata = task_info.get('metadata', {})
    gt_keywords = metadata.get('ground_truth_keywords', {})

    # Copy result file
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

    score = 0
    feedback = []

    # 1. History Evidence (15 pts)
    history_hits = result.get('history_hits', 0)
    if history_hits >= 1:
        score += 15
        feedback.append("History check passed (visited CareerOneStop).")
    else:
        feedback.append("History check failed: No visits to careeronestop.org detected.")

    # 2. Bookmarks (30 pts)
    folder_exists = result.get('bookmark_folder_exists', False)
    bookmarks_count = result.get('bookmarks_in_folder', 0)
    
    if folder_exists:
        score += 15
        feedback.append("'State Boards' bookmark folder found.")
        if bookmarks_count >= 3:
            score += 15
            feedback.append(f"Found {bookmarks_count} bookmarks in folder (target >= 3).")
        else:
            score += (bookmarks_count * 5)
            feedback.append(f"Found only {bookmarks_count} bookmarks in folder (target >= 3).")
    else:
        feedback.append("'State Boards' bookmark folder NOT found.")

    # 3. Report Existence (15 pts)
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_fresh', False)
    
    if report_exists and report_fresh:
        score += 15
        feedback.append("Report file exists and was created during task.")
    elif report_exists:
        score += 5
        feedback.append("Report file exists but was NOT created during task (stale?).")
    else:
        feedback.append("Report file not found.")

    # 4. Report Content (40 pts)
    content = result.get('report_content')
    if isinstance(content, dict):
        # Structure check (10 pts)
        states_found = 0
        target_states = ["arizona", "maryland", "washington"]
        
        # Handle case where agent puts states under a "states" key or at root
        # Check root first, then 'states' key
        data_to_check = content
        if 'states' in content and isinstance(content['states'], dict):
            data_to_check = content['states']
            
        # Normalize keys to lowercase for checking
        data_keys_lower = {k.lower(): v for k, v in data_to_check.items()}
        
        for state in target_states:
            if state in data_keys_lower:
                states_found += 1
        
        if states_found == 3:
            score += 10
            feedback.append("Report structure correct (all 3 states found).")
        else:
            score += int((states_found / 3) * 10)
            feedback.append(f"Report structure incomplete ({states_found}/3 states found).")

        # Content Accuracy (30 pts - 10 per state)
        for state in target_states:
            state_score = 0
            if state in data_keys_lower:
                entry = data_keys_lower[state]
                auth = str(entry.get('authority_name', '')).lower()
                renew = str(entry.get('renewal_frequency', '')).lower()
                
                gt = gt_keywords.get(state, {})
                
                # Check Authority Name
                auth_match = any(k.lower() in auth for k in gt.get('authority', []))
                if auth_match:
                    state_score += 5
                
                # Check Renewal
                renew_match = any(k.lower() in renew for k in gt.get('renewal', []))
                if renew_match:
                    state_score += 5
                
                score += state_score
                if state_score < 10:
                    feedback.append(f"{state.title()} data partial match ({state_score}/10).")
            else:
                feedback.append(f"{state.title()} missing from report.")

    elif content == "INVALID_JSON":
        feedback.append("Report file contains invalid JSON.")
    else:
        feedback.append("Report content missing or unreadable.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }