#!/usr/bin/env python3
"""Verifier for BOM Cost Rollup and Explosion Analysis task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (2+ signals required)."""
    if not gui_evidence:
        return False, 0.0, "No GUI evidence"
    signals = 0
    details = []
    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU:{gui_evidence['mru_connection_count']}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"sessions:{gui_evidence['sqldev_oracle_sessions']}")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"history:{gui_evidence['sql_history_count']}")
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), "; ".join(details) or "No signals"


def verify_bom_cost_explosion_analysis(traj, env_info, task_info):
    """
    Verify BOM cost explosion task completion.

    Scoring (100 pts total):
    1. Circular References (20 pts):
       - cycles_fixed -> 15 pts
       - fix_log_exists & count >= 3 -> 5 pts
    2. Hierarchy Views (25 pts):
       - explosion_vw_exists -> 5 pts
       - explosion_connect_used & explosion_path_used -> 10 pts
       - where_used_exists & where_used_connect_used -> 10 pts
    3. MRP Requirements Generation (25 pts):
       - mrp_proc_exists -> 10 pts
       - mrp_req_table_exists & ws5000_requirements > 0 -> 15 pts
    4. Cost Summary (10 pts):
       - cost_summary_mv_exists -> 5 pts
       - rollup_used -> 5 pts
    5. CSV Export (10 pts):
       - csv_exists & csv_size > 50 -> 10 pts
    6. GUI Usage (10 pts):
       - 2+ signals -> 10 pts

    Pass threshold: 60 pts AND cycles_fixed AND at least one view/procedure created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/bom_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        cycles_fixed = result.get('cycles_fixed', False)
        remaining_cycles = result.get('remaining_cycles', 99)
        fix_log_exists = result.get('fix_log_exists', False)
        fix_log_count = result.get('fix_log_count', 0)
        
        explosion_vw_exists = result.get('explosion_vw_exists', False)
        explosion_connect_used = result.get('explosion_connect_used', False)
        explosion_path_used = result.get('explosion_path_used', False)
        
        where_used_exists = result.get('where_used_exists', False)
        where_used_connect_used = result.get('where_used_connect_used', False)
        
        mrp_proc_exists = result.get('mrp_proc_exists', False)
        mrp_req_table_exists = result.get('mrp_req_table_exists', False)
        ws5000_requirements = result.get('ws5000_requirements', 0)
        
        cost_summary_mv_exists = result.get('cost_summary_mv_exists', False)
        rollup_used = result.get('rollup_used', False)
        
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        
        gui_evidence = result.get('gui_evidence', {})
        
        # 1. Circular References
        if cycles_fixed:
            score += 15
            feedback_parts.append("Circular references fixed (15/15)")
        else:
            feedback_parts.append(f"Circular references NOT fixed. Remaining: {remaining_cycles} (0/15)")
            
        if fix_log_exists and fix_log_count >= 3:
            score += 5
            feedback_parts.append("BOM fix log populated (5/5)")
        elif fix_log_exists:
            score += 2
            feedback_parts.append(f"BOM fix log exists but incomplete ({fix_log_count} rows) (2/5)")
            
        # 2. Hierarchy Views
        if explosion_vw_exists:
            score += 5
            if explosion_connect_used and explosion_path_used:
                score += 10
                feedback_parts.append("Explosion view correctly uses CONNECT BY and SYS_CONNECT_BY_PATH (15/15)")
            else:
                feedback_parts.append("Explosion view missing correct hierarchical functions (5/15)")
        else:
            feedback_parts.append("Explosion view not found (0/15)")
            
        if where_used_exists:
            if where_used_connect_used:
                score += 10
                feedback_parts.append("Where-used view correctly uses CONNECT BY (10/10)")
            else:
                score += 5
                feedback_parts.append("Where-used view exists but missing CONNECT BY (5/10)")
                
        # 3. MRP Procedure
        if mrp_proc_exists:
            score += 10
            feedback_parts.append("MRP procedure exists (10/10)")
            
        if mrp_req_table_exists and ws5000_requirements > 0:
            score += 15
            feedback_parts.append(f"MRP requirements calculated for WS-5000 with {ws5000_requirements} rows (15/15)")
        elif mrp_req_table_exists:
            score += 5
            feedback_parts.append("MRP requirements table exists but missing WS-5000 rows (5/15)")
            
        # 4. Cost Summary MV
        if cost_summary_mv_exists:
            score += 5
            if rollup_used:
                score += 5
                feedback_parts.append("Cost summary MV correctly uses ROLLUP (10/10)")
            else:
                feedback_parts.append("Cost summary MV missing ROLLUP (5/10)")
                
        # 5. CSV Export
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append("CSV exported successfully (10/10)")
        elif csv_exists:
            score += 5
            feedback_parts.append("CSV exported but file is very small or empty (5/10)")
            
        # 6. GUI Usage
        gui_used, gui_score_mult, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (10/10)")
        else:
            feedback_parts.append(f"Insufficient GUI usage evidence [{gui_details}] (0/10)")

        # Evaluate passing criteria
        key_criteria_met = cycles_fixed and (explosion_vw_exists or mrp_proc_exists or cost_summary_mv_exists)
        passed = score >= 60 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error in verifier: {str(e)}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with exception: {str(e)}"}