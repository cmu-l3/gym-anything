#!/usr/bin/env python3
"""
Verifier for analyze_customer_affinity task.

Checks:
1. 'DeepCatalogCustomers' query exists in ODB file.
2. SQL structure contains required clauses (JOIN, GROUP BY, HAVING, etc.).
3. Query executes correctly against reference data and produces expected rows.
4. 'Various Artists' is excluded.
5. VLM verification of the final state.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_customer_affinity(traj, env_info, task_info):
    """
    Verify the LibreOffice Base task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # Extract analysis data
    analysis = result.get('analysis', {})
    odb_modified = result.get('odb_modified', False)
    app_running = result.get('app_running', False)
    
    # --- Criterion 1: App State & File Persistence (15 pts) ---
    if app_running:
        score += 5
    else:
        feedback_parts.append("LibreOffice was not running at end")

    if odb_modified:
        score += 10
        feedback_parts.append("Database file saved")
    else:
        feedback_parts.append("Database file NOT saved/modified")

    # --- Criterion 2: Query Existence (10 pts) ---
    if analysis.get('query_found'):
        score += 10
        feedback_parts.append("Query 'DeepCatalogCustomers' found")
    else:
        feedback_parts.append("Query 'DeepCatalogCustomers' NOT found")
        # Critical failure if query missing
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # --- Criterion 3: SQL Logic/Structure (30 pts) ---
    if analysis.get('sql_structure_valid'):
        score += 30
        feedback_parts.append("SQL structure valid (JOINs, Aggregation, Filter)")
    else:
        # Partial credit for existing SQL
        score += 10
        feedback_parts.append("SQL structure missing required elements (GROUP BY, HAVING, or filtering)")

    # --- Criterion 4: Execution Accuracy (25 pts) ---
    results_match = analysis.get('results_match')
    execution_success = analysis.get('execution_success')
    row_count = analysis.get('row_count', 0)
    gt_count = analysis.get('ground_truth_row_count', 0)
    
    if results_match is True:
        score += 25
        feedback_parts.append("Query results match ground truth perfectly")
    elif results_match == "partial":
        score += 15
        feedback_parts.append("Query results mostly match ground truth")
    elif execution_success:
        # It ran but results were wrong
        diff = abs(row_count - gt_count)
        if diff <= 2 and gt_count > 0:
            score += 15
            feedback_parts.append(f"Row count close to expected ({row_count} vs {gt_count})")
        else:
            score += 5
            feedback_parts.append(f"Query ran but returned wrong row count ({row_count} vs {gt_count})")
    else:
        feedback_parts.append(f"SQL execution failed: {analysis.get('error', 'unknown error')}")

    # --- Criterion 5: VLM Verification (20 pts) ---
    # Check if they actually did the work using UI or SQL editor
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        vlm_prompt = (
            "Does this screenshot show LibreOffice Base? "
            "Can you see a query named 'DeepCatalogCustomers' in the list, "
            "OR a SQL query editor window open with code? "
            "Ignore other windows."
        )
        vlm_res = query_vlm(image=final_screenshot, prompt=vlm_prompt)
        
        if vlm_res.get('success'):
            if "yes" in vlm_res.get('parsed', {}).get('answer', '').lower() or \
               "query" in vlm_res.get('parsed', {}).get('answer', '').lower():
                score += 20
                feedback_parts.append("Visual verification passed")
            else:
                score += 10 # Grace points if ambiguous
        else:
            score += 10 # Grace points if VLM fails
    else:
        feedback_parts.append("No screenshot available")

    # Final tally
    passed = score >= 70 and analysis.get('query_found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }