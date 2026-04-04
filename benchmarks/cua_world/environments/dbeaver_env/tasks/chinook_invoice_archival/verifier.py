#!/usr/bin/env python3
"""
Verifier for chinook_invoice_archival task.

Verifies:
1. Agent created and connected to both DBs in DBeaver.
2. Archive DB contains correct data (migration success).
3. Working DB no longer contains archived data (cleanup success).
4. Summary table in Working DB has correct aggregates.
5. Reconciliation CSV exists and seems valid.
"""

import json
import os
import sys
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_invoice_archival(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # Load Ground Truth
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/ground_truth.json", gt_file.name)
        with open(gt_file.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {str(e)}"}
    finally:
        os.unlink(gt_file.name)

    # Load Agent Result
    res_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/archival_result.json", res_file.name)
        with open(res_file.name, 'r') as f:
            res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        os.unlink(res_file.name)

    score = 0
    feedback = []
    
    # 1. Check Connections (10 pts)
    if res.get('dbeaver_conn_working') and res.get('dbeaver_conn_archive'):
        score += 10
        feedback.append("Both DBeaver connections created.")
    elif res.get('dbeaver_conn_working') or res.get('dbeaver_conn_archive'):
        score += 5
        feedback.append("Only one DBeaver connection found.")
    else:
        feedback.append("No DBeaver connections found.")

    # 2. Check Archive DB Content (30 pts)
    # Check invoice count
    expected_arch_inv = gt['archive']['total_invoices']
    actual_arch_inv = res.get('archive_inv_count', 0)
    
    # Check item count (referential integrity check implied if counts match)
    expected_arch_items = gt['archive']['total_items']
    actual_arch_items = res.get('archive_item_count', 0)

    if abs(actual_arch_inv - expected_arch_inv) == 0:
        score += 15
        feedback.append(f"Archive invoice count correct ({actual_arch_inv}).")
    else:
        feedback.append(f"Archive invoice count incorrect. Got {actual_arch_inv}, expected {expected_arch_inv}.")

    if abs(actual_arch_items - expected_arch_items) == 0:
        score += 15
        feedback.append(f"Archive items count correct ({actual_arch_items}).")
    else:
        feedback.append(f"Archive items count incorrect. Got {actual_arch_items}, expected {expected_arch_items}.")

    # 3. Check Working DB Cleanup (20 pts)
    # Should be 0 for 2009/2010
    cleanup_2009 = res.get('working_2009_count', -1)
    cleanup_2010 = res.get('working_2010_count', -1)
    
    if cleanup_2009 == 0 and cleanup_2010 == 0:
        score += 20
        feedback.append("Working database cleaned up successfully.")
    else:
        feedback.append(f"Working database still contains archived data (2009: {cleanup_2009}, 2010: {cleanup_2010}).")

    # 4. Check Summary Table (20 pts)
    if res.get('summary_table_exists'):
        # Check revenues
        gt_rev_09 = gt['archive']['2009']['revenue']
        gt_rev_10 = gt['archive']['2010']['revenue']
        
        agent_rev_09 = res.get('summary_2009_rev', 0)
        agent_rev_10 = res.get('summary_2010_rev', 0)
        
        rev_ok = False
        if math.isclose(agent_rev_09, gt_rev_09, rel_tol=0.05) and math.isclose(agent_rev_10, gt_rev_10, rel_tol=0.05):
            rev_ok = True
        
        if rev_ok:
            score += 20
            feedback.append("Summary table revenue values are correct.")
        else:
            score += 10
            feedback.append(f"Summary table exists but values diverge (>5%). Expected approx {gt_rev_09:.2f}/{gt_rev_10:.2f}, got {agent_rev_09:.2f}/{agent_rev_10:.2f}.")
    else:
        feedback.append("Summary table 'archived_yearly_summary' not found in working DB.")

    # 5. Check CSV (20 pts)
    if res.get('csv_exists'):
        if res.get('csv_has_rows'):
            score += 20
            feedback.append("Reconciliation CSV created with content.")
        else:
            score += 10
            feedback.append("Reconciliation CSV created but appears empty/incomplete.")
    else:
        feedback.append("Reconciliation CSV not found.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }