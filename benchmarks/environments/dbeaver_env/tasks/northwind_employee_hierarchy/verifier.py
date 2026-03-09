#!/usr/bin/env python3
"""
Verifier for northwind_employee_hierarchy task.
Scores based on:
1. DBeaver connection configuration
2. Existence and correctness of hierarchy_report.csv
3. Existence and correctness of manager_summary.csv (requires recursive logic)
4. Existence of SQL script
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_northwind_employee_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hierarchy_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Connection (10 pts)
    conn = result.get('connection', {})
    if conn.get('found') and conn.get('correct_db'):
        score += 10
        feedback.append("DBeaver connection 'NorthwindHR' configured correctly.")
    elif conn.get('found'):
        score += 5
        feedback.append("DBeaver connection found but might point to wrong DB.")
    else:
        feedback.append("DBeaver connection 'NorthwindHR' NOT found.")

    # 2. Files Existence (15 pts)
    files = result.get('files', {})
    if files.get('hierarchy_exists'): score += 5
    if files.get('manager_exists'): score += 5
    if files.get('sql_exists'): score += 5
    
    if not files.get('created_during_task'):
        feedback.append("WARNING: Files not created during task execution (timestamp check failed).")
        # Severe penalty for anti-gaming
        score = 0 
        return {"passed": False, "score": 0, "feedback": "Files were not created during the task window."}

    # 3. Hierarchy Report Verification (35 pts)
    agent_data = result.get('agent_data', {})
    gt = result.get('ground_truth', {})
    
    # Check Columns (10 pts)
    req_h_cols = ['employeeid', 'fullname', 'title', 'managername', 'managementlevel', 'directreportcount']
    agent_h_cols = agent_data.get('hierarchy_cols', [])
    missing_h = [c for c in req_h_cols if c not in agent_h_cols]
    if not missing_h:
        score += 10
    else:
        feedback.append(f"Hierarchy report missing columns: {missing_h}")

    # Check Top Level Logic (15 pts)
    # The top manager (Andrew Fuller) should be level 0
    if agent_data.get('top_level_level') == 0:
        score += 15
    else:
        feedback.append("Hierarchy root (Level 0) not correctly identified in CSV.")

    # Check Row Count (10 pts)
    # Should match ground truth employee count (9)
    if agent_data.get('hierarchy_rows') == gt.get('employee_count', 9):
        score += 10
    else:
        feedback.append(f"Hierarchy row count mismatch. Expected {gt.get('employee_count')}, got {agent_data.get('hierarchy_rows')}.")

    # 4. Manager Summary Verification (40 pts) - The Hard Part
    # Check Columns (10 pts)
    req_m_cols = ['managername', 'title', 'directreportcount', 'totalsubordinates', 'maxdepthbelow']
    agent_m_cols = agent_data.get('manager_cols', [])
    missing_m = [c for c in req_m_cols if c not in agent_m_cols]
    if not missing_m:
        score += 10
    else:
        feedback.append(f"Manager summary missing columns: {missing_m}")

    # Check Andrew Fuller Stats (Recursive Check) (30 pts)
    # This verifies if they actually did the recursive query correctly
    af_stats = agent_data.get('andrew_fuller_stats', {})
    gt_af = gt.get('managers', {}).get(gt.get('top_manager_name'), {})
    
    if not gt_af:
        # Fallback if names don't match exactly in GT generation
        # Find the manager with max total subordinates in GT
        max_subs = -1
        for m in gt.get('managers', {}).values():
            if m['total_subordinates'] > max_subs:
                max_subs = m['total_subordinates']
                gt_af = m

    try:
        agent_direct = int(float(af_stats.get('direct', -1)))
        agent_total = int(float(af_stats.get('total', -1)))
        
        gt_direct = gt_af.get('direct_reports')
        gt_total = gt_af.get('total_subordinates')

        # Direct reports (Easier) (10 pts)
        if agent_direct == gt_direct:
            score += 10
        else:
            feedback.append(f"Manager direct reports mismatch. Expected {gt_direct}, got {agent_direct}.")

        # Total subordinates (Recursive/Deep) (20 pts)
        if agent_total == gt_total:
            score += 20
        else:
            feedback.append(f"Manager total subordinates (recursive) mismatch. Expected {gt_total}, got {agent_total}. Did you use a recursive query?")
            
    except (ValueError, TypeError):
        feedback.append("Could not parse numeric stats for Top Manager.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }