#!/usr/bin/env python3
"""
Verifier for custom_link_position_audit task.

Verifies:
1. Exported CSV exists and contains "Link Position" data.
2. Custom Link Position names (Header, Footer, Sidebar, Main_Content) appear in the export.
3. Report file exists and contains analysis.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_link_position_audit(traj, env_info, task_info):
    """
    Verify the custom link position audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    feedback_parts = []
    
    # Criteria 1: CSV Export (20 pts)
    if result.get("csv_exists", False):
        if result.get("csv_valid", False):
            score += 20
            feedback_parts.append("Valid CSV export found")
        else:
            score += 10
            feedback_parts.append("CSV found but appears empty/small")
    else:
        feedback_parts.append("No CSV export found")

    # Criteria 2: Configuration Success - Header/Footer (20 pts)
    # These are easier to get accidentally, but we check specifically for "Header" "Footer" strings
    found_hf = 0
    if result.get("found_header", False): found_hf += 10
    if result.get("found_footer", False): found_hf += 10
    
    score += found_hf
    if found_hf == 20:
        feedback_parts.append("Header/Footer positions detected")
    elif found_hf > 0:
        feedback_parts.append("Partial Header/Footer positions detected")

    # Criteria 3: Configuration Success - Sidebar/Main (20 pts)
    # These are the distinctive custom ones
    found_sm = 0
    if result.get("found_sidebar", False): found_sm += 10
    if result.get("found_main", False): found_sm += 10
    
    score += found_sm
    if found_sm == 20:
        feedback_parts.append("Sidebar/Main_Content positions detected")
    elif found_sm > 0:
        feedback_parts.append("Partial Sidebar/Main positions detected")

    # Criteria 4: Data Integrity (20 pts)
    if result.get("domain_match", False) and result.get("row_count", 0) > 100:
        score += 20
        feedback_parts.append("Correct domain crawled with significant data")
    elif result.get("domain_match", False):
        score += 10
        feedback_parts.append("Correct domain but low row count")
    else:
        feedback_parts.append("Domain data missing/incorrect")

    # Criteria 5: Report (20 pts)
    if result.get("report_exists", False):
        if result.get("report_content_valid", False):
            score += 20
            feedback_parts.append("Analysis report found with valid content")
        else:
            score += 10
            feedback_parts.append("Report file found but content validation failed")
    else:
        feedback_parts.append("No report file found")

    # Final Check
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }