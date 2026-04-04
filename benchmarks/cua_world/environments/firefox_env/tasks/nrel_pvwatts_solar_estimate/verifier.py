#!/usr/bin/env python3
"""
Verifier for nrel_pvwatts_solar_estimate task.

Criteria:
1. CSV Download (30 pts): 'pvwatts_hourly*.csv' exists in Downloads and size > 1KB.
2. Report Accuracy (30 pts): 'solar_production_report.txt' contains value between 13,000 and 16,000.
3. Bookmarks (20 pts): 'Client Estimates' folder exists with NREL link.
4. History (10 pts): Visited pvwatts.nrel.gov.
5. Freshness (10 pts): Files created during task.

Pass Threshold: 60/100
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nrel_pvwatts_solar_estimate(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected ranges from metadata
    metadata = task_info.get('metadata', {})
    min_kwh = metadata.get('expected_min_kwh', 13000)
    max_kwh = metadata.get('expected_max_kwh', 16000)

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/nrel_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 3. Evaluate CSV Download (30 pts)
    csv_exists = result.get('csv_exists', False)
    csv_size = int(result.get('csv_size', 0))
    
    if csv_exists and csv_size > 1024: # > 1KB
        score += 30
        feedback.append("CSV download verification passed.")
    elif csv_exists:
        score += 10
        feedback.append("CSV file found but appears empty or too small.")
    else:
        feedback.append("CSV output file not found in Downloads.")

    # 4. Evaluate Report Accuracy (30 pts)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "")
    
    value_found = False
    extracted_val = 0
    
    if report_exists:
        # Look for number pattern like "14,200" or "14200"
        # Regex: Look for digits, optional comma, digits, maybe "kWh"
        matches = re.findall(r'(\d{1,3}(?:,\d{3})*|\d{4,})', report_content)
        
        for m in matches:
            # Clean comma
            val = int(m.replace(',', ''))
            # Check if it looks like an annual production figure (10k - 20k)
            if 10000 <= val <= 20000:
                extracted_val = val
                value_found = True
                break
        
        if value_found:
            if min_kwh <= extracted_val <= max_kwh:
                score += 30
                feedback.append(f"Report accuracy passed: {extracted_val} kWh is within expected range ({min_kwh}-{max_kwh}).")
            else:
                score += 10 # Partial credit for finding a number, but wrong one
                feedback.append(f"Report value {extracted_val} kWh is outside expected range ({min_kwh}-{max_kwh}). Did you use the correct location (Phoenix) and size (8kW)?")
        else:
            feedback.append("Report file exists but no valid annual production number found.")
    else:
        feedback.append("Report file not found.")

    # 5. Evaluate Bookmarks (20 pts)
    if result.get('bookmark_folder_found', False) and result.get('bookmark_link_found', False):
        score += 20
        feedback.append("Bookmark verification passed.")
    elif result.get('bookmark_folder_found', False):
        score += 10
        feedback.append("Bookmark folder 'Client Estimates' found, but NREL link missing.")
    else:
        feedback.append("Bookmark folder 'Client Estimates' not found.")

    # 6. Evaluate History (10 pts)
    if result.get('history_found', False):
        score += 10
        feedback.append("Browser history verification passed.")
    else:
        feedback.append("NREL PVWatts URL not found in browser history.")

    # 7. Evaluate Freshness (10 pts)
    # If report was created during task, give points
    if result.get('report_fresh', False):
        score += 10
        feedback.append("File freshness verification passed.")
    elif report_exists:
        feedback.append("Report file exists but has old timestamp (pre-task).")

    # Final Verdict
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }