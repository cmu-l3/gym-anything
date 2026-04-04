#!/usr/bin/env python3
"""
Verifier for hierarchy_salary_rollup task.

Verification Logic:
1. Agent Output File (30 pts): Checks /home/ga/salary_rollup.json for correct calculation.
2. Database Schema (20 pts): Checks if Staff and ReportsTo classes exist.
3. Database Data (30 pts): Checks if correct number of vertices (8) and edges (7) exist.
4. Hierarchy Integrity (20 pts): Checks a specific edge (Bob -> Alice) to verify directionality.

Pass Threshold: 85 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hierarchy_salary_rollup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # Metadata expectations
    expected_total = task_info.get('metadata', {}).get('expected_total_salary', 535000)
    expected_count = task_info.get('metadata', {}).get('expected_staff_count', 6)

    # 1. Verify Database Schema (20 pts)
    schema_data = result.get('db_schema_result', {}).get('result', [])
    class_names = [item.get('name') for item in schema_data]
    
    if 'Staff' in class_names and 'ReportsTo' in class_names:
        score += 20
        feedback_parts.append("Schema created correctly (Staff, ReportsTo)")
    else:
        feedback_parts.append(f"Schema missing required classes. Found: {class_names}")

    # 2. Verify Data Counts (30 pts)
    # Expect 8 staff members
    staff_count = result.get('db_staff_count', 0)
    # Expect 7 edges for a single-root tree of 8 nodes
    edge_count = result.get('db_edge_count', 0)

    if staff_count == 8:
        score += 15
        feedback_parts.append("Staff count correct (8)")
    else:
        feedback_parts.append(f"Incorrect Staff count: {staff_count}/8")

    if edge_count == 7:
        score += 15
        feedback_parts.append("ReportsTo edge count correct (7)")
    else:
        feedback_parts.append(f"Incorrect ReportsTo edge count: {edge_count}/7")

    # 3. Verify Hierarchy Structure (20 pts)
    # We checked specifically for Bob -> Alice in the export script
    hierarchy_sample = result.get('db_hierarchy_sample', 0)
    if hierarchy_sample >= 1:
        score += 20
        feedback_parts.append("Hierarchy structure verified (Bob->Alice edge exists)")
    else:
        feedback_parts.append("Hierarchy edge missing or wrong direction (Bob should report to Alice)")

    # 4. Verify Calculation / Output File (30 pts)
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not file_exists:
        feedback_parts.append("Output file /home/ga/salary_rollup.json not found")
    elif not file_created:
        feedback_parts.append("Output file exists but was not created during task")
    else:
        file_content = result.get('file_content', {})
        # Normalize keys just in case
        calc_total = file_content.get('total_subtree_salary', 0)
        calc_count = file_content.get('staff_count', 0)
        
        # Check Total Salary
        if calc_total == expected_total:
            score += 15
            feedback_parts.append(f"Salary calculation correct ({calc_total})")
        else:
            feedback_parts.append(f"Salary calculation incorrect (Expected {expected_total}, got {calc_total})")
            
        # Check Staff Count
        if calc_count == expected_count:
            score += 15
            feedback_parts.append(f"Subtree staff count correct ({calc_count})")
        else:
            feedback_parts.append(f"Subtree staff count incorrect (Expected {expected_count}, got {calc_count})")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }