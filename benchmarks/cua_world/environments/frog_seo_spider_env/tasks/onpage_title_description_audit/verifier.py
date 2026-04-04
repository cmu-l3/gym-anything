#!/usr/bin/env python3
"""
Verifier for onpage_title_description_audit task.
Checks CSV exports and report content.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_onpage_title_description_audit(traj, env_info, task_info):
    """
    Verify that the user crawled the site, analyzed titles/descriptions, 
    exported the correct CSVs, and wrote a summary report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_csv_rows = metadata.get('min_csv_rows', 20)

    score = 0
    feedback_parts = []
    
    # Load result
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

    # 1. Page Titles CSV (30 pts)
    # 15 for valid file existence, 15 for sufficient data
    if result.get('titles_csv_valid', False):
        score += 15
        count = result.get('titles_row_count', 0)
        if count >= min_csv_rows:
            score += 15
            feedback_parts.append(f"Titles CSV valid ({count} rows)")
        else:
            score += 5
            feedback_parts.append(f"Titles CSV valid but low row count ({count})")
    else:
        feedback_parts.append("Titles CSV missing or invalid")

    # 2. Meta Descriptions CSV (30 pts)
    if result.get('descriptions_csv_valid', False):
        score += 15
        count = result.get('descriptions_row_count', 0)
        if count >= min_csv_rows:
            score += 15
            feedback_parts.append(f"Descriptions CSV valid ({count} rows)")
        else:
            score += 5
            feedback_parts.append(f"Descriptions CSV valid but low row count ({count})")
    else:
        feedback_parts.append("Descriptions CSV missing or invalid")

    # 3. Audit Report (30 pts)
    # 10 for existence/size, 10 for numbers, 10 for keywords
    if result.get('report_exists', False) and result.get('report_size', 0) > 100:
        score += 10
        if result.get('report_has_numbers', False):
            score += 10
        else:
            feedback_parts.append("Report missing numeric counts")
            
        if result.get('report_has_keywords', False):
            score += 10
        else:
            feedback_parts.append("Report missing 'title'/'description' keywords")
            
        feedback_parts.append("Report file verified")
    else:
        feedback_parts.append("Report file missing or too short")

    # 4. App Usage / VLM (10 pts)
    # For now, base this on SF running or implicit success of other steps
    if result.get('sf_running', False) or score > 0:
        score += 10

    # VLM Verification (Enhancement)
    # If we have VLM capability, we could verify the agent actually visited the tabs
    # For this implementation, we stick to the robust file-based signals which
    # cover 90% of the intent.

    passed = (score >= 60) and result.get('titles_csv_valid') and result.get('descriptions_csv_valid')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }