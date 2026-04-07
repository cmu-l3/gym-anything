#!/usr/bin/env python3
"""Verifier for Retail Fair Workweek Compliance Audit task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (1+ signals required)."""
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
    
    # We only need 1 good signal from SQL Developer to prove it wasn't just sqlplus
    gui_used = signals >= 1
    return gui_used, min(signals / 2, 1.0), "; ".join(details) or "No signals"


def verify_retail_fair_workweek_compliance_audit(traj, env_info, task_info):
    """
    Verify retail fair workweek compliance audit task.

    Scoring (100 pts total):
    1. Clopening View (20 pts):
       - Exists (10 pts)
       - LAG analytic function used (10 pts)
    2. Predictive Scheduling View (15 pts):
       - Exists (15 pts)
    3. Meal Break View (15 pts):
       - Exists (15 pts)
    4. Penalty Materialized View (20 pts):
       - Exists (10 pts)
       - NVL/COALESCE used (10 pts)
    5. Math Accuracy (15 pts):
       - Total sum equals 111 (15 pts) -> (50 + 25 + 18 + 18)
    6. CSV Export (10 pts):
       - Exists and size > 0 (10 pts)
    7. GUI Usage (5 pts):
       - 1+ signals (5 pts)

    Pass threshold: 70 pts AND Penalty MV exists.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/compliance_audit_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Extract result fields
        clopening_vw_exists = result.get('clopening_vw_exists', False)
        predictive_vw_exists = result.get('predictive_vw_exists', False)
        meal_break_vw_exists = result.get('meal_break_vw_exists', False)
        penalty_mv_exists = result.get('penalty_mv_exists', False)
        agent_total = float(result.get('agent_total', 0))
        lag_used = result.get('lag_used', False)
        nvl_coalesce_used = result.get('nvl_coalesce_used', False)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        
        gui_evidence = {k: v for k, v in result.items() if k in 
                        ['mru_connection_count', 'sqldev_oracle_sessions', 'sql_history_count']}

        # 1. Clopening View (20 pts)
        if clopening_vw_exists:
            score += 10
            if lag_used:
                score += 10
                feedback_parts.append("Clopening view exists & uses LAG (20/20)")
            else:
                feedback_parts.append("Clopening view exists but lacks LAG function (10/20)")
        else:
            feedback_parts.append("Clopening view missing (0/20)")

        # 2. Predictive Scheduling (15 pts)
        if predictive_vw_exists:
            score += 15
            feedback_parts.append("Predictive scheduling view exists (15/15)")
        else:
            feedback_parts.append("Predictive scheduling view missing (0/15)")

        # 3. Meal Break (15 pts)
        if meal_break_vw_exists:
            score += 15
            feedback_parts.append("Meal break view exists (15/15)")
        else:
            feedback_parts.append("Meal break view missing (0/15)")

        # 4. Penalty MV (20 pts)
        if penalty_mv_exists:
            score += 10
            if nvl_coalesce_used:
                score += 10
                feedback_parts.append("Penalty MV exists & handles NULLs (20/20)")
            else:
                feedback_parts.append("Penalty MV exists but lacks NVL/COALESCE (10/20)")
        else:
            feedback_parts.append("Penalty MV missing (0/20)")

        # 5. Math Accuracy (15 pts)
        # Expected deterministic total based on setup_task.sh seed is 111.0
        expected_total = 111.0
        if penalty_mv_exists:
            if abs(agent_total - expected_total) < 0.1:
                score += 15
                feedback_parts.append(f"Penalty sum is perfectly accurate: {agent_total} (15/15)")
            else:
                feedback_parts.append(f"Penalty sum inaccurate: got {agent_total}, expected {expected_total} (0/15)")
        else:
            feedback_parts.append("Cannot evaluate math without Penalty MV (0/15)")

        # 6. CSV Export (10 pts)
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append("CSV exported successfully (10/10)")
        elif csv_exists:
            score += 5
            feedback_parts.append("CSV exists but is very small/empty (5/10)")
        else:
            feedback_parts.append("CSV export missing (0/10)")

        # 7. GUI Usage (5 pts)
        gui_used, _, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 5
            feedback_parts.append(f"GUI usage detected [{gui_details}] (5/5)")
        else:
            feedback_parts.append(f"No GUI usage detected [{gui_details}] (0/5)")

        # Evaluate Pass/Fail
        passed = score >= 70 and penalty_mv_exists

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }