#!/usr/bin/env python3
"""
Verifier for Voyage Fuel Analysis Task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_voyage_fuel_analysis(traj, env_info, task_info):
    """
    Verify the fuel analysis report.
    
    Criteria:
    1. Report file exists and was created during the task (10 pts).
    2. Report format roughly matches requirements (contains segments) (20 pts).
    3. Total fuel calculated matches ground truth within tolerance (70 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    tol_percent = metadata.get('tolerance_percent', 1.0)
    tol_abs = metadata.get('tolerance_absolute', 0.5)

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extraction
    report_exists = result.get("report_exists", False)
    report_created = result.get("report_created_during_task", False)
    report_content = result.get("report_content_preview", "")
    ground_truth = result.get("ground_truth", {})
    
    gt_total_fuel = ground_truth.get("total_fuel", 0.0)
    gt_num_legs = ground_truth.get("num_legs", 0)

    score = 0
    feedback_parts = []

    # Criterion 1: File Exists & Freshness (10 pts)
    if report_exists and report_created:
        score += 10
        feedback_parts.append("Report file created successfully.")
    elif report_exists:
        score += 5
        feedback_parts.append("Report file exists but timestamp is suspicious.")
    else:
        feedback_parts.append("Report file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Criterion 2: Content Parsing (20 pts)
    # Check for "TOTAL FUEL" keyword and reasonable structure
    if "TOTAL FUEL" in report_content.upper():
        score += 10
    else:
        feedback_parts.append("Report missing 'TOTAL FUEL' label.")

    # Check if we see roughly the right number of segments mentioned
    # Look for "Leg" or "Segment" keywords
    segment_mentions = len(re.findall(r'(Leg|Segment)\s*\d+', report_content, re.IGNORECASE))
    if segment_mentions >= gt_num_legs:
        score += 10
        feedback_parts.append(f"Found {segment_mentions} segment details.")
    elif segment_mentions > 0:
        score += 5
        feedback_parts.append(f"Found some segment details ({segment_mentions}), expected {gt_num_legs}.")
    else:
        feedback_parts.append("No leg/segment details found in report.")

    # Criterion 3: Accuracy (70 pts)
    # Extract the value
    agent_val = result.get("extracted_fuel_value", -1.0)
    
    # If regex in export script failed, try harder here or give specific feedback
    if agent_val < 0:
        # Try one more regex variation just in case
        match = re.search(r'REQUIRED:?\s*(\d+\.?\d*)', report_content, re.IGNORECASE)
        if match:
            try:
                agent_val = float(match.group(1))
            except:
                pass

    if agent_val < 0:
        feedback_parts.append("Could not parse a numeric total fuel value from the report.")
    else:
        # Check tolerance
        # Tolerance is max(percentage error, absolute error)
        diff = abs(agent_val - gt_total_fuel)
        percent_diff = (diff / gt_total_fuel) * 100.0 if gt_total_fuel > 0 else 0
        
        is_accurate = False
        if diff <= tol_abs:
            is_accurate = True
        elif percent_diff <= tol_percent:
            is_accurate = True
            
        if is_accurate:
            score += 70
            feedback_parts.append(f"Fuel calculation accurate! (Agent: {agent_val:.2f}, GT: {gt_total_fuel:.2f})")
        else:
            # Partial credit for being close (e.g., within 10%)
            if percent_diff <= 10.0:
                score += 30
                feedback_parts.append(f"Fuel value close but outside tolerance (Agent: {agent_val:.2f}, GT: {gt_total_fuel:.2f}, Diff: {percent_diff:.1f}%). Check interpolation or distance formula.")
            else:
                feedback_parts.append(f"Fuel value incorrect (Agent: {agent_val:.2f}, GT: {gt_total_fuel:.2f}).")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }