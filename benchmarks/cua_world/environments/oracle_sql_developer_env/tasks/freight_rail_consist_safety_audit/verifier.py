#!/usr/bin/env python3
"""Verifier for Freight Rail Consist Safety Audit task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_freight_rail_consist_safety_audit(traj, env_info, task_info):
    """
    Scoring System (100 points total):
    1. Overloaded Cars View (15 pts): exists (5) + correct count=3 (10)
    2. Train Power Audit View (15 pts): exists (5) + correct count=2 (10)
    3. Hazmat Violations View (35 pts): exists (10) + window functions used (10) + correct count=4 (15)
    4. Manifest Summary MV (15 pts): exists (5) + rollup/cube used (10)
    5. CSV Export (10 pts): file exists and is not empty
    6. GUI Usage (10 pts): IDE was utilized

    Pass threshold: 70 pts AND hazmat view exists AND GUI usage confirmed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.path.exists(temp_file.name) and os.unlink(temp_file.name)
            
        score = 0
        feedback = []
        
        # 1. Overloaded Cars View
        if result.get('overloaded_cars_vw_exists'):
            score += 5
            count = result.get('overloaded_count', 0)
            if count == 3:
                score += 10
                feedback.append("Overloaded Cars View accurate (15/15)")
            else:
                feedback.append(f"Overloaded Cars View exists but count is {count}, expected 3 (5/15)")
        else:
            feedback.append("Overloaded Cars View missing (0/15)")
            
        # 2. Train Power Audit View
        if result.get('train_power_audit_vw_exists'):
            score += 5
            count = result.get('underpowered_count', 0)
            if count == 2:
                score += 10
                feedback.append("Train Power Audit View accurate (15/15)")
            else:
                feedback.append(f"Train Power Audit View exists but count is {count}, expected 2 (5/15)")
        else:
            feedback.append("Train Power Audit View missing (0/15)")
            
        # 3. Hazmat Violations View
        hazmat_exists = result.get('hazmat_vw_exists', False)
        if hazmat_exists:
            score += 10
            if result.get('hazmat_window_used'):
                score += 10
                feedback.append("Hazmat View uses window functions (10/10)")
            else:
                feedback.append("Hazmat View missing LAG/LEAD window functions (0/10)")
                
            count = result.get('hazmat_count', 0)
            if count == 4:
                score += 15
                feedback.append("Hazmat View correctly identified 4 violations (15/15)")
            else:
                feedback.append(f"Hazmat View identified {count} violations, expected 4 (0/15)")
        else:
            feedback.append("Hazmat Violations View missing (0/35)")
            
        # 4. Manifest Summary MV
        if result.get('manifest_mv_exists'):
            score += 5
            if result.get('manifest_rollup_used'):
                score += 10
                feedback.append("Manifest Summary MV uses ROLLUP/CUBE (15/15)")
            else:
                feedback.append("Manifest Summary MV missing ROLLUP/CUBE (5/15)")
        else:
            feedback.append("Manifest Summary MV missing (0/15)")
            
        # 5. CSV Export
        if result.get('csv_exists') and result.get('csv_size', 0) > 0:
            score += 10
            feedback.append("CSV export created successfully (10/10)")
        else:
            feedback.append("CSV export missing or empty (0/10)")
            
        # 6. GUI Usage
        gui_evidence = result.get('gui_evidence', {})
        signals = sum(1 for k in ['sql_history_count', 'mru_connection_count', 'sqldev_oracle_sessions'] if gui_evidence.get(k, 0) > 0)
        
        gui_used = False
        if signals >= 2 or gui_evidence.get('window_title_changed', False):
            score += 10
            gui_used = True
            feedback.append("GUI usage confirmed (10/10)")
        else:
            feedback.append("No active GUI usage detected (0/10)")
            
        # Final pass criteria
        passed = score >= 70 and hazmat_exists and gui_used
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }
        
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with exception: {str(e)}"}