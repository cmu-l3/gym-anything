#!/usr/bin/env python3
"""
Verifier for log_historical_visitor_entry task.

Criteria:
1. Export file exists (proof of data entry + ability to export).
2. Export file contains the visitor name "Emmett Brown".
3. Export file contains "Future Industries".
4. Export file contains the CORRECT date (Yesterday).
5. VLM verification of the process (optional but good for robustness).
"""

import json
import tempfile
import os
import base64
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_historical_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []
    
    # 1. Check Export Existence
    if not result.get('export_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No export file found at /home/ga/Documents/verification_export.*. Please export the log to verify your entry."
        }
    
    score += 20
    feedback.append("Export file found")

    # 2. Decode Content
    content_b64 = result.get('export_content_base64', "")
    content = ""
    if content_b64 and content_b64 != "BINARY_FILE":
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        except:
            content = ""
            feedback.append("Could not decode export file content")
    elif content_b64 == "BINARY_FILE":
        feedback.append("Export is binary format (xls), content check limited")
        # For binary files, we might give benefit of doubt if VLM passes or fail if text required
        # Task description asked for csv/txt/xls. 
        # If binary, we can't verify content easily without libraries. 
        # We'll assume for now the user followed instructions and used CSV/TXT if possible, 
        # or we rely on VLM if content is unreadable.
    
    # 3. Verify Visitor Details
    content_lower = content.lower()
    
    # Name Check
    if "emmett" in content_lower and "brown" in content_lower:
        score += 20
        feedback.append("Visitor name 'Emmett Brown' found in log")
    else:
        feedback.append("Visitor name 'Emmett Brown' NOT found in export")

    # Company Check
    if "future" in content_lower or "industries" in content_lower:
        score += 10
        feedback.append("Company 'Future Industries' found in log")
    else:
        feedback.append("Company details missing from export")

    # 4. Verify Date (The Core Challenge)
    target_us = result.get('target_date_us', '')   # MM/DD/YYYY
    target_iso = result.get('target_date_iso', '') # YYYY-MM-DD
    
    # Logic: Look for the date string in the content
    # We strip years to 2 digits to be flexible (2024 vs 24)
    # 05/19/2024 -> 05/19/24
    
    date_found = False
    
    if target_us and target_us in content:
        date_found = True
    elif target_iso and target_iso in content:
        date_found = True
    elif target_us:
        # Try short year format
        short_year_us = target_us[:-4] + target_us[-2:] # MM/DD/YY
        if short_year_us in content:
            date_found = True
            
    if date_found:
        score += 40
        feedback.append(f"Correct historical date ({target_us}) found in log")
    else:
        feedback.append(f"Correct date ({target_us}) NOT found in export. Did you backdate the record?")

    # 5. Check Time (Rough check)
    if "9:00" in content or "09:00" in content:
        score += 5
        feedback.append("Check-in time (9:00) found")
    
    if "10:30" in content:
        score += 5
        feedback.append("Check-out time (10:30) found")

    # Final Pass Calculation
    # Must have Export + Name + Date
    passed = (result.get('export_found') and 
              ("emmett" in content_lower) and 
              date_found)
              
    if passed:
        # Ensure score is at least 70 if passed
        score = max(score, 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }