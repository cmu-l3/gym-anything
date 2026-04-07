#!/usr/bin/env python3
"""
Verifier for price_sync_merge task.

Verifies:
1. MERGE statement logic (Inserts vs Updates vs No-Change)
2. OUTPUT clause usage (Audit logging)
3. Schema correctness (Audit table columns)
4. View creation
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_price_sync_merge(traj, env_info, task_info):
    """
    Verify the MERGE statement task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # 1. Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_expected = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/merge_result.json", temp_result.name)
        copy_from_env("/tmp/merge_expected.json", temp_expected.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        with open(temp_expected.name, 'r') as f:
            expected = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_expected.name): os.unlink(temp_expected.name)

    score = 0
    feedback = []
    
    # Extract Data
    audit_table = result.get('audit_table', {})
    audit_stats = result.get('audit_stats', {})
    view_check = result.get('view_check', {})
    
    exp_updates = expected.get('expected_updates', 0)
    exp_inserts = expected.get('expected_inserts', 0)
    init_master = expected.get('initial_master_count', 0)
    final_master = result.get('master_final_count', 0)

    # Criterion 1: Audit Table Structure (20 pts)
    if audit_table.get('Exists', 0) == 1:
        score += 10
        if audit_table.get('ColCount', 0) >= 8: # AuditID, Action, PID, Name, Old, New, Pct, TS
            score += 10
            feedback.append("Audit table structure correct.")
        else:
            feedback.append("Audit table missing required columns.")
    else:
        feedback.append("Audit table Pricing.MergeAuditLog not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 2: Logic Verification - INSERTs (15 pts)
    # The number of inserts in audit log should match expected new products
    actual_inserts = audit_stats.get('InsertRows', 0)
    if abs(actual_inserts - exp_inserts) <= 1:
        score += 15
        feedback.append(f"Correctly inserted {actual_inserts} new products.")
    else:
        feedback.append(f"Incorrect INSERT count. Expected ~{exp_inserts}, got {actual_inserts}.")

    # Criterion 3: Logic Verification - UPDATEs (15 pts)
    # The number of updates should match expected price changes
    actual_updates = audit_stats.get('UpdateRows', 0)
    if abs(actual_updates - exp_updates) <= 2:
        score += 15
        feedback.append(f"Correctly updated {actual_updates} product prices.")
    else:
        feedback.append(f"Incorrect UPDATE count. Expected ~{exp_updates}, got {actual_updates}.")

    # Criterion 4: Logic Verification - Filtering Unchanged (10 pts)
    # Crucial: Did they update rows where price didn't change?
    spurious = audit_stats.get('SpuriousUpdates', 0)
    if spurious == 0 and actual_updates > 0:
        score += 10
        feedback.append("Correctly filtered out unchanged prices.")
    elif spurious > 0:
        feedback.append(f"Logged {spurious} updates where OldPrice == NewPrice (Inefficient).")
    
    # Criterion 5: PriceMaster Final State (10 pts)
    # Final count should be Initial + Inserts
    expected_final = init_master + exp_inserts
    if abs(final_master - expected_final) <= 1:
        score += 10
        feedback.append("Target table PriceMaster has correct final row count.")
    else:
        feedback.append(f"PriceMaster row count mismatch. Expected {expected_final}, got {final_master}.")

    # Criterion 6: Summary View (20 pts)
    if view_check.get('ViewExists', 0) == 1:
        score += 10
        if view_check.get('ViewRows', 0) > 0:
            score += 10
            feedback.append("Summary view created and functional.")
        else:
            feedback.append("Summary view exists but returns no data.")
    else:
        feedback.append("View Pricing.vw_MergeSummary not found.")

    # Criterion 7: VLM Check (10 pts)
    # Verify ADS was actually used and we aren't seeing a generic error screen
    if query_vlm:
        final_ss = get_final_screenshot(traj)
        frames = sample_trajectory_frames(traj, 5)
        
        vlm_res = query_vlm(
            prompt="Is this Azure Data Studio or a SQL editor showing a query or database tables?",
            images=frames + [final_ss]
        )
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', False):
             score += 10
             feedback.append("VLM confirmed Azure Data Studio usage.")
        else:
             # Fallback if VLM unsure, but verify timestamps programmatically
             if result.get('timestamp_valid', 0) == 1:
                 score += 10
                 feedback.append("Audit timestamps validated (fallback).")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": "\n".join(feedback)
    }