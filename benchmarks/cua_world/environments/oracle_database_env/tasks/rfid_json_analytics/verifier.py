#!/usr/bin/env python3
"""
Verifier for rfid_json_analytics task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rfid_json_analytics(traj, env_info, task_info):
    """
    Verifies the RFID JSON Analytics task.
    Checks:
    1. RFID_EVENTS_FLAT view exists, has correct columns, and data.
    2. ZONE_TRAFFIC_SUMMARY view exists, has aggregation columns.
    3. GET_TAG_HISTORY function exists, returns pipe-delimited string, handles missing tags.
    4. Export file exists and contains report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_flat_cols = set(metadata.get('flat_view_columns', []))
    required_summary_cols = set(metadata.get('summary_view_columns', []))

    # Load result
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
    feedback_parts = []
    
    # 1. Check Flat View (30 pts)
    flat_view = result.get("views", {}).get("RFID_EVENTS_FLAT", {})
    if flat_view.get("exists"):
        score += 10
        feedback_parts.append("RFID_EVENTS_FLAT created")
        
        # Check columns
        actual_cols = set(flat_view.get("columns", []))
        missing = required_flat_cols - actual_cols
        if not missing:
            score += 10
            feedback_parts.append("Flat view columns correct")
        else:
            score += 5
            feedback_parts.append(f"Flat view missing columns: {list(missing)[:3]}...")
            
        # Check data
        if flat_view.get("row_count", 0) >= 500:
            score += 10
            feedback_parts.append("Flat view data extraction working")
    else:
        feedback_parts.append("RFID_EVENTS_FLAT view not found")

    # 2. Check Summary View (25 pts)
    sum_view = result.get("views", {}).get("ZONE_TRAFFIC_SUMMARY", {})
    if sum_view.get("exists"):
        score += 10
        feedback_parts.append("ZONE_TRAFFIC_SUMMARY created")
        
        # Check aggregation columns
        actual_cols = set(sum_view.get("columns", []))
        if "AVG_SIGNAL_STRENGTH" in actual_cols and "TOTAL_READS" in actual_cols:
            score += 10
            feedback_parts.append("Summary columns present")
            
        # Check logic
        if result.get("data_checks", {}).get("sum_matches_total"):
            score += 5
    else:
        feedback_parts.append("ZONE_TRAFFIC_SUMMARY view not found")

    # 3. Check Function (25 pts)
    func = result.get("function", {})
    if func.get("exists") and func.get("status") == "VALID":
        score += 10
        feedback_parts.append("GET_TAG_HISTORY function exists")
        
        output = func.get("test_output", "")
        if "|" in output and ":" in output:
            score += 10
            feedback_parts.append("Function returns correct pipe format")
        
        if "NO_EVENTS_FOUND" in func.get("error_handling_output", ""):
            score += 5
            feedback_parts.append("Function handles missing tags")
    else:
        feedback_parts.append("GET_TAG_HISTORY function missing or invalid")

    # 4. Check Export File (20 pts)
    file_info = result.get("file", {})
    if file_info.get("exists"):
        score += 10
        if file_info.get("size", 0) > 100:
            score += 10
            feedback_parts.append("Report file exported")
        else:
            feedback_parts.append("Report file empty/small")
    else:
        feedback_parts.append("Report file not found")

    passed = score >= 60 and flat_view.get("exists") and sum_view.get("exists")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }