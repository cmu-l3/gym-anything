#!/usr/bin/env python3
"""
Verifier for export_legacy_sales_report task.

Verification Strategy:
1. File Existence (20 pts): Check if /home/ga/Documents/last_month_sales.csv exists.
2. File Freshness (20 pts): Check if file was created during the task window.
3. CSV Format (20 pts): Check if headers match standard WooCommerce export.
4. Data Integrity (20 pts): Check if file contains data rows (not just headers).
5. Date Accuracy (20 pts): Check if data corresponds to "Last Month".

Backup Check:
- If file is in Downloads but not Documents, partial credit.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_legacy_sales_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. File Existence
    file_exists = result.get('file_exists', False)
    download_found = result.get('download_found_in_downloads', False)
    
    if file_exists:
        score += 20
        feedback_parts.append("File found at correct location")
    elif download_found:
        score += 10
        feedback_parts.append("File found in Downloads but not moved to Documents")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. File Freshness
    if result.get('created_during_task', False):
        score += 20
        feedback_parts.append("File created during task")
    else:
        # If we found a download in Downloads that is new, give points
        if download_found and not file_exists:
             score += 10
             feedback_parts.append("Download is fresh")
        elif file_exists:
             feedback_parts.append("File timestamp is old (pre-task)")
    
    # Stop if we don't have a valid file to parse
    if not file_exists and not download_found:
         return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. CSV Headers
    headers = result.get('headers', "")
    expected_header_part = "Date,Orders,Gross Sales"
    
    # Flexible check for headers (sometimes quoted)
    if expected_header_part in headers or "Date" in headers and "Gross Sales" in headers:
        score += 20
        feedback_parts.append("Valid CSV headers")
    else:
        feedback_parts.append(f"Invalid headers: {headers[:50]}...")

    # 4. Data Integrity (Content Check)
    sample_data = result.get('sample_data', "")
    if len(sample_data.strip()) > 0:
        score += 20
        feedback_parts.append("File contains data rows")
    else:
        feedback_parts.append("File appears empty (headers only?)")

    # 5. Date Accuracy
    has_target_data = result.get('has_target_month_data', False)
    expected_month = result.get('expected_month_prefix', 'UNKNOWN')
    
    if has_target_data:
        score += 20
        feedback_parts.append(f"Data matches target month ({expected_month})")
    else:
        feedback_parts.append(f"Data does not contain entries for {expected_month}")

    # Final verification
    passed = score >= 80  # Requires file correct loc, fresh, headers, data
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }