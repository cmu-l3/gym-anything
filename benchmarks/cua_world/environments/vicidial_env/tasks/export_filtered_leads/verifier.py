#!/usr/bin/env python3
"""
Verifier for export_filtered_leads task.

Criteria:
1. File created in Downloads (20 pts)
2. File is valid CSV/Text (20 pts)
3. Data contains correct rows (State=FL, List=9001) (30 pts)
4. Data does NOT contain wrong rows (State!=FL) (20 pts)
5. Admin log evidence of search/export (10 pts)
"""

import json
import os
import base64
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_filtered_leads(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    target_state = metadata.get('target_state', 'FL')
    target_list = metadata.get('target_list_id', '9001')
    expected_count = metadata.get('expected_count', 2)

    # Load result
    import tempfile
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
    
    # 1. File Existence (20 pts)
    if not result.get('file_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No exported file found in ~/Downloads created during the task window."
        }
    
    score += 20
    feedback.append("File created in Downloads.")
    
    # 2. Parse Content (Text/CSV check) (20 pts)
    content_b64 = result.get('file_content_base64', '')
    if not content_b64:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Exported file is empty."
        }

    try:
        content_str = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        return {"passed": False, "score": score, "feedback": "Failed to decode file content."}

    # Vicidial exports can be messy (headers, tabs, etc). We try to detect delimiter.
    # We look for the presence of the known data lines.
    # Data to look for: "Florida", "Man", "Miami", "Vice"
    # Data to AVOID: "Empire", "State", "Golden", "Gate"
    
    lines = content_str.splitlines()
    if len(lines) < 2:
        return {"passed": False, "score": score, "feedback": "File content too short (less than 2 lines)."}
    
    score += 20
    feedback.append("File content is readable.")

    # 3. Verify Data Content (30 pts + 20 pts)
    # We count occurrences of target keywords and exclusion keywords
    # This is more robust than strict CSV parsing given Vicidial's variable export formats
    
    # FL Leads
    found_fl_1 = "Florida" in content_str or "3055550001" in content_str
    found_fl_2 = "Miami" in content_str or "3055550002" in content_str
    
    # Non-FL Leads (Should NOT be present)
    found_ny_1 = "Empire" in content_str or "2125550001" in content_str
    found_ca_1 = "Golden" in content_str or "4155550001" in content_str
    
    correct_leads_found = 0
    if found_fl_1: correct_leads_found += 1
    if found_fl_2: correct_leads_found += 1
    
    wrong_leads_found = 0
    if found_ny_1: wrong_leads_found += 1
    if found_ca_1: wrong_leads_found += 1
    
    # Scoring Data Accuracy
    # Max 30 for finding correct leads (15 per lead)
    data_score = (correct_leads_found / expected_count) * 30
    score += int(data_score)
    
    if correct_leads_found == expected_count:
        feedback.append(f"Found all {expected_count} target Florida leads.")
    elif correct_leads_found > 0:
        feedback.append(f"Found partial target leads ({correct_leads_found}/{expected_count}).")
    else:
        feedback.append("No target Florida leads found in file.")

    # Scoring Filtering (Max 20 for NOT finding wrong leads)
    # If any wrong lead is found, we penalize.
    if wrong_leads_found == 0:
        score += 20
        feedback.append("Correctly filtered out non-FL leads.")
    else:
        feedback.append(f"Failed to filter: Found {wrong_leads_found} non-FL leads in the export.")

    # 4. Admin Log Check (10 pts)
    # Did they actually use the UI?
    if result.get('admin_log_activity', False):
        score += 10
        feedback.append("Admin log confirms search/export activity.")
    else:
        feedback.append("Warning: No 'SEARCH' or 'EXPORT' activity found in admin logs (did you use the UI?).")

    # Pass Threshold: 70
    # Must have file (40), some correct data (15+), and filtering (20) roughly.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }