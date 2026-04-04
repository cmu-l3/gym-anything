#!/usr/bin/env python3
import json
import logging
import os
import sys
import tempfile
import re

logger = logging.getLogger(__name__)

def verify_fcc_license_audit(traj, env_info, task_info):
    """
    Verifies the FCC License Audit task.
    Criteria:
    1. Firefox History: Visited FCC ULS (10 pts)
    2. Bookmarks: 'FCC Audits' folder exists (20 pts) containing >= 2 links (10 pts)
    3. JSON File: Exists & Valid (10 pts)
    4. Data Accuracy: W1AW details (20 pts) & W6YX details (20 pts)
    5. Dates: Fields present (10 pts)
    """
    
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Metadata for validation
    meta = task_info.get('metadata', {})
    expected_w1aw_frn = meta.get('w1aw_frn', '0002534816')
    expected_w6yx_frn = meta.get('w6yx_frn', '0003507852')

    # --- Criterion 1: History (10 pts) ---
    if result.get('history_found'):
        score += 10
        feedback.append("FCC ULS history found (+10)")
    else:
        feedback.append("No FCC ULS history found")

    # --- Criterion 2: Bookmarks (30 pts) ---
    if result.get('bookmark_folder_found'):
        score += 20
        feedback.append("'FCC Audits' folder found (+20)")
        
        count = result.get('bookmarks_in_folder', 0)
        if count >= 2:
            score += 10
            feedback.append(f"Folder contains {count} bookmarks (+10)")
        else:
            feedback.append(f"Folder contains only {count} bookmarks (expected >= 2)")
    else:
        feedback.append("'FCC Audits' bookmark folder not found")

    # --- Criterion 3: JSON File Existence (10 pts) ---
    file_content = result.get('file_content', {})
    if result.get('file_exists') and result.get('file_fresh') and isinstance(file_content, dict) and file_content:
        score += 10
        feedback.append("Audit JSON file created successfully (+10)")
    else:
        feedback.append("Audit JSON file missing, empty, or not created during task")
        # Critical failure for data checking, but we continue scoring what we can
    
    # --- Criterion 4: Data Accuracy (40 pts) ---
    # Normalize keys to handle case sensitivity
    data = {k.upper(): v for k, v in file_content.items()}
    
    # Check W1AW
    w1aw = data.get('W1AW')
    if w1aw:
        # Check FRN
        found_frn = str(w1aw.get('frn', '')).strip()
        if expected_w1aw_frn in found_frn:
            score += 10
            feedback.append("W1AW FRN correct (+10)")
        else:
            feedback.append(f"W1AW FRN incorrect: got '{found_frn}'")
            
        # Check Status
        if str(w1aw.get('status', '')).lower() == 'active':
            score += 10
            feedback.append("W1AW Status active (+10)")
        else:
            feedback.append("W1AW Status incorrect or missing")
    else:
        feedback.append("W1AW entry missing in JSON")

    # Check W6YX
    w6yx = data.get('W6YX')
    if w6yx:
        # Check FRN
        found_frn = str(w6yx.get('frn', '')).strip()
        if expected_w6yx_frn in found_frn:
            score += 10
            feedback.append("W6YX FRN correct (+10)")
        else:
            feedback.append(f"W6YX FRN incorrect: got '{found_frn}'")
            
        # Check Status
        if str(w6yx.get('status', '')).lower() == 'active':
            score += 10
            feedback.append("W6YX Status active (+10)")
        else:
            feedback.append("W6YX Status incorrect or missing")
    else:
        feedback.append("W6YX entry missing in JSON")

    # --- Criterion 5: Dates (10 pts) ---
    # Just check if date fields exist and look vaguely like dates
    date_score = 0
    date_pattern = re.compile(r'\d{1,4}[-/]\d{1,2}[-/]\d{1,4}')
    
    total_dates_checked = 0
    dates_found = 0
    
    for entry in [w1aw, w6yx]:
        if entry:
            for field in ['grant_date', 'expiration_date']:
                total_dates_checked += 1
                val = str(entry.get(field, ''))
                if date_pattern.search(val):
                    dates_found += 1

    if total_dates_checked > 0 and dates_found >= 3: # Allow one missing/malformed date
        score += 10
        feedback.append("License dates recorded correctly (+10)")
    elif dates_found > 0:
        score += 5
        feedback.append("Some license dates missing or malformed (+5)")
    else:
        feedback.append("License dates missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }