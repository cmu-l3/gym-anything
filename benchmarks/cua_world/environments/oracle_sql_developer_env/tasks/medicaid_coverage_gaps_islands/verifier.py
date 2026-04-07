#!/usr/bin/env python3
"""Verifier for Medicaid Coverage Gaps and Islands task."""

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
    return gui_used, min(signals / 2, 1.0), "; ".join(details) or "No signals"

def verify_medicaid_coverage_gaps_islands(traj, env_info, task_info):
    """
    Verify completion of the Medicaid Gaps and Islands Analysis task.

    Scoring (100 pts total):
    1. CONTINUOUS_COVERAGE_VW (25 pts)
       - Exists: 10 pts
       - Correct rows (10 expected): 15 pts
    2. COVERAGE_GAPS_VW (20 pts)
       - Exists: 10 pts
       - Correct rows (5 expected): 10 pts
    3. HEDIS_METRICS_2023 Table (25 pts)
       - Exists: 5 pts
       - Correct Y count (3): 10 pts
       - Correct N count (2): 10 pts
    4. PROC_REFRESH_METRICS Procedure (10 pts)
       - Exists: 5 pts
       - Valid: 5 pts
    5. CSV Export (10 pts)
       - Exists & Newer than start: 5 pts
       - Size > 50 bytes: 5 pts
    6. GUI Usage Evidence (10 pts)
       - Evidence found: 10 pts

    Pass threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/medicaid_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Metadata expectations
        metadata = task_info.get('metadata', {})
        expected_episodes = metadata.get('expected_episodes_count', 10)
        expected_gaps = metadata.get('expected_gaps_count', 5)
        expected_y = metadata.get('expected_hedis_y', 3)
        expected_n = metadata.get('expected_hedis_n', 2)

        # 1. CONTINUOUS_COVERAGE_VW (25 pts)
        if result.get('continuous_vw_exists'):
            score += 10
            feedback_parts.append("CONTINUOUS_COVERAGE_VW exists (10/10)")
            rows = result.get('continuous_rows', 0)
            if rows == expected_episodes:
                score += 15
                feedback_parts.append(f"Continuous episodes correctly consolidated: {rows} (15/15)")
            else:
                feedback_parts.append(f"Continuous episodes count incorrect. Expected {expected_episodes}, got {rows} (0/15)")
        else:
            feedback_parts.append("CONTINUOUS_COVERAGE_VW not found (0/25)")

        # 2. COVERAGE_GAPS_VW (20 pts)
        if result.get('gaps_vw_exists'):
            score += 10
            feedback_parts.append("COVERAGE_GAPS_VW exists (10/10)")
            rows = result.get('gaps_rows', 0)
            if rows == expected_gaps:
                score += 10
                feedback_parts.append(f"Gaps correctly calculated: {rows} (10/10)")
            else:
                feedback_parts.append(f"Gaps count incorrect. Expected {expected_gaps}, got {rows} (0/10)")
        else:
            feedback_parts.append("COVERAGE_GAPS_VW not found (0/20)")

        # 3. HEDIS_METRICS_2023 Table (25 pts)
        if result.get('hedis_tbl_exists'):
            score += 5
            feedback_parts.append("HEDIS_METRICS_2023 table exists (5/5)")
            
            y_count = result.get('hedis_meets_y', 0)
            n_count = result.get('hedis_meets_n', 0)
            
            if y_count == expected_y:
                score += 10
                feedback_parts.append(f"HEDIS 'Y' count correct: {y_count} (10/10)")
            else:
                feedback_parts.append(f"HEDIS 'Y' count incorrect. Expected {expected_y}, got {y_count} (0/10)")
                
            if n_count == expected_n:
                score += 10
                feedback_parts.append(f"HEDIS 'N' count correct: {n_count} (10/10)")
            else:
                feedback_parts.append(f"HEDIS 'N' count incorrect. Expected {expected_n}, got {n_count} (0/10)")
        else:
            feedback_parts.append("HEDIS_METRICS_2023 table not found (0/25)")

        # 4. PROC_REFRESH_METRICS Procedure (10 pts)
        if result.get('proc_exists'):
            score += 5
            feedback_parts.append("PROC_REFRESH_METRICS exists (5/5)")
            if result.get('proc_valid'):
                score += 5
                feedback_parts.append("PROC_REFRESH_METRICS is VALID (5/5)")
            else:
                feedback_parts.append("PROC_REFRESH_METRICS is INVALID (0/5)")
        else:
            feedback_parts.append("PROC_REFRESH_METRICS not found (0/10)")

        # 5. CSV Export (10 pts)
        if result.get('csv_exists'):
            if result.get('csv_newer'):
                score += 5
                feedback_parts.append("CSV exported during task (5/5)")
                if result.get('csv_size', 0) > 50:
                    score += 5
                    feedback_parts.append("CSV size valid (5/5)")
                else:
                    feedback_parts.append("CSV is empty or too small (0/5)")
            else:
                feedback_parts.append("CSV is stale (created before task) (0/10)")
        else:
            feedback_parts.append("CSV export not found (0/10)")

        # 6. GUI Usage Evidence (10 pts)
        gui_used, gui_ratio, gui_details = _check_gui_usage(result.get('gui_evidence', {}))
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (10/10)")
        else:
            feedback_parts.append(f"No GUI usage detected [{gui_details}] (0/10)")

        passed = score >= 70
        
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
            "feedback": f"Verification error: {str(e)}"
        }