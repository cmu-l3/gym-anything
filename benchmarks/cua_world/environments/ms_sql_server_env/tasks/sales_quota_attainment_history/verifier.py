#!/usr/bin/env python3
"""
Verifier for sales_quota_attainment_history task.
Verifies SQL View logic (temporal derivation, range joins) and CSV export.
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sales_quota_attainment_history(traj, env_info, task_info):
    """
    Score the task based on:
    1. View existence and schema (20 pts)
    2. Logic correctness - verified by comparing Agent's View against Ground Truth query (50 pts)
    3. CSV Export existence and validity (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. View Existence (10 pts)
    if result.get('view_exists', 0) == 1:
        score += 10
        feedback.append("View 'Sales.vw_HistoricalQuotaAttainment' exists.")
    else:
        feedback.append("View 'Sales.vw_HistoricalQuotaAttainment' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Column Check (10 pts)
    required_columns = task_info['metadata']['required_columns']
    found_columns = result.get('columns_found', '').split(',')
    # Case-insensitive check
    found_lower = [c.lower() for c in found_columns]
    missing = [c for c in required_columns if c.lower() not in found_lower]
    
    if not missing:
        score += 10
        feedback.append("All required columns present.")
    else:
        feedback.append(f"Missing columns: {', '.join(missing)}")
        # Continue checking logic even if columns strictly named wrong, if possible

    # 3. Logic Verification (Test Case) (50 pts)
    # Compares ground truth values calculated in export_result.sh vs what the agent's view returned
    test_case = result.get('test_case', {})
    
    try:
        gt_actual = float(test_case.get('gt_actual', -1))
        gt_attainment = float(test_case.get('gt_attainment', -1))
        agent_actual = float(test_case.get('agent_actual', -1))
        agent_attainment = float(test_case.get('agent_attainment', -1))
        
        # Check Actual Sales (Range Join Logic)
        if math.isclose(gt_actual, agent_actual, rel_tol=0.01):
            score += 25
            feedback.append(f"Actual Sales calculation correct ({agent_actual}).")
        else:
            feedback.append(f"Actual Sales incorrect. Expected ~{gt_actual}, got {agent_actual}. Likely incorrect date range logic.")

        # Check Attainment Pct (Arithmetic)
        if math.isclose(gt_attainment, agent_attainment, rel_tol=0.01):
            score += 15
            feedback.append(f"Attainment % calculation correct ({agent_attainment}%).")
        else:
            feedback.append(f"Attainment % incorrect. Expected ~{gt_attainment}%, got {agent_attainment}%.")
            
        # Check End Date Logic (LEAD function)
        # We expect the agent to have a valid date here, not NULL, even for a mid-history record
        agent_quota_end = test_case.get('agent_quota_end', '')
        if agent_quota_end and agent_quota_end.strip() != '' and agent_quota_end.strip() != 'NULL':
            score += 10
            feedback.append("QuotaEndDate derivation logic appears valid.")
        else:
            feedback.append("QuotaEndDate is empty or NULL.")
            
    except (ValueError, TypeError):
        feedback.append("Could not compare logic values (data missing or malformed).")

    # 4. CSV Verification (30 pts)
    csv_info = result.get('csv_file', {})
    if csv_info.get('exists'):
        score += 10
        feedback.append("CSV file exists.")
        
        if csv_info.get('created_during_task'):
            score += 10
            feedback.append("CSV created during task.")
        else:
            feedback.append("CSV timestamp predates task start (Anti-Gaming).")
            
        if csv_info.get('content_valid') and csv_info.get('row_count', 0) > 0:
            score += 10
            feedback.append(f"CSV content valid ({csv_info.get('row_count')} rows).")
    else:
        feedback.append("CSV file not found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }