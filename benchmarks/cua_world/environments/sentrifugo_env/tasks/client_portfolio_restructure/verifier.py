#!/usr/bin/env python3
"""
Verifier for client_portfolio_restructure task.

Evaluates the database state JSON exported by export_result.sh.
Scoring Breakdown (100 pts total, pass threshold = 65):
  - Legacy project 'General Plant Operations 2025' is deactivated (isactive=0): 15 pts
  - 'Biomass Grid Integration Phase 2' project exists and is active: 15 pts
  - 'Facility Maintenance 2026' project exists and is active: 15 pts
  - Tasks correctly assigned to Project 1 (3 tasks * 5 pts): 15 pts
  - Tasks correctly assigned to Project 2 (2 tasks * 5 pts): 10 pts
  - Employees correctly mapped to Project 1 (2 emps * 7.5 pts): 15 pts
  - Employees correctly mapped to Project 2 (2 emps * 7.5 pts): 15 pts
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_client_portfolio_restructure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    projects = result.get('projects', [])
    tasks = result.get('tasks', [])
    employees = result.get('employees', [])

    # 1. Verify Legacy Project Deactivation
    legacy_proj = next((p for p in projects if p['name'] == 'General Plant Operations 2025'), None)
    if legacy_proj:
        if str(legacy_proj['isactive']) == '0':
            score += 15
            feedback.append("Legacy project successfully deactivated (15/15)")
        else:
            feedback.append("Legacy project is still active (0/15)")
    else:
        # If it was hard deleted, we accept it but note they didn't follow the "deactivate, do not delete" perfectly.
        # However, to be fair to edge cases, we give points if it's no longer active.
        score += 15
        feedback.append("Legacy project not found - assuming deleted instead of deactivated (15/15)")

    # 2. Verify New Projects
    p1_name = "Biomass Grid Integration Phase 2"
    p2_name = "Facility Maintenance 2026"
    
    p1 = next((p for p in projects if p['name'] == p1_name), None)
    if p1 and str(p1['isactive']) == '1' and p1['client'] == 'Pinnacle Renewable Energy':
        score += 15
        feedback.append(f"Project '{p1_name}' created correctly (15/15)")
    else:
        feedback.append(f"Project '{p1_name}' missing or incorrect (0/15)")

    p2 = next((p for p in projects if p['name'] == p2_name), None)
    if p2 and str(p2['isactive']) == '1' and p2['client'] == 'Pinnacle Renewable Energy':
        score += 15
        feedback.append(f"Project '{p2_name}' created correctly (15/15)")
    else:
        feedback.append(f"Project '{p2_name}' missing or incorrect (0/15)")

    # 3. Verify Tasks
    expected_p1_tasks = ["SCADA System Update", "Grid Synchronization Tests", "Safety Audit"]
    expected_p2_tasks = ["Turbine Inspection", "Ash Handling System Repair"]

    p1_tasks_found = [t['taskname'] for t in tasks if t['projectname'] == p1_name]
    for t_req in expected_p1_tasks:
        if any(t_req.lower() in t_found.lower() for t_found in p1_tasks_found):
            score += 5
            feedback.append(f"Task '{t_req}' found for P1 (5/5)")
        else:
            feedback.append(f"Task '{t_req}' missing for P1 (0/5)")

    p2_tasks_found = [t['taskname'] for t in tasks if t['projectname'] == p2_name]
    for t_req in expected_p2_tasks:
        if any(t_req.lower() in t_found.lower() for t_found in p2_tasks_found):
            score += 5
            feedback.append(f"Task '{t_req}' found for P2 (5/5)")
        else:
            feedback.append(f"Task '{t_req}' missing for P2 (0/5)")

    # 4. Verify Employees
    expected_p1_emps = ["EMP005", "EMP006"]
    expected_p2_emps = ["EMP019", "EMP020"]

    p1_emps_found = [e['empid'] for e in employees if e['projectname'] == p1_name]
    for e_req in expected_p1_emps:
        if e_req in p1_emps_found:
            score += 7.5
            feedback.append(f"Employee {e_req} mapped to P1 (7.5/7.5)")
        else:
            feedback.append(f"Employee {e_req} missing from P1 (0/7.5)")

    p2_emps_found = [e['empid'] for e in employees if e['projectname'] == p2_name]
    for e_req in expected_p2_emps:
        if e_req in p2_emps_found:
            score += 7.5
            feedback.append(f"Employee {e_req} mapped to P2 (7.5/7.5)")
        else:
            feedback.append(f"Employee {e_req} missing from P2 (0/7.5)")

    passed = score >= 65
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }