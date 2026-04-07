#!/usr/bin/env python3
"""Verifier for DMV License Suspension Audit task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dmv_audit(traj, env_info, task_info):
    """
    Verify DMV License Suspension Audit task completion.

    Scoring (100 pts total):
    1. Window Function View (25 pts):
       - vw_rolling_exists -> 10 pts
       - has_range_interval -> 10 pts
       - has_preceding -> 5 pts
    2. Audit View Logic (30 pts):
       - vw_audit_exists -> 10 pts
       - exact ground truth missing count (25) -> 10 pts
       - exact ground truth invalid count (15) -> 10 pts
    3. Materialized Summary (15 pts):
       - mv_summary_exists -> 5 pts
       - rollups match views -> 10 pts
    4. Data Export (15 pts):
       - exists and modified during task -> 5 pts
       - >0 size and contains expected missing records -> 5 pts
       - properly filtered (does not contain 'OK') -> 5 pts
    5. GUI Evidence (15 pts):
       - Telemetry proves SQL Developer UI usage -> 15 pts

    Pass threshold: 70 pts AND at least partial success on window function logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    expected_missing = ground_truth.get('missing_suspension_count', 25)
    expected_invalid = ground_truth.get('invalid_suspension_count', 15)

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/dmv_audit_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Window Function View (25 pts)
        vw_rolling_exists = result.get('vw_rolling_exists', False)
        has_range = result.get('has_range_interval', False)
        has_preceding = result.get('has_preceding', False)
        
        if vw_rolling_exists:
            score += 10
            feedback_parts.append("CITATION_ROLLING_POINTS_VW exists (10/10)")
            if has_range:
                score += 10
                feedback_parts.append("RANGE BETWEEN INTERVAL detected (10/10)")
            else:
                feedback_parts.append("RANGE BETWEEN INTERVAL missing (0/10)")
            if has_preceding:
                score += 5
                feedback_parts.append("PRECEDING detected (5/5)")
            else:
                feedback_parts.append("PRECEDING missing (0/5)")
        else:
            feedback_parts.append("CITATION_ROLLING_POINTS_VW missing (0/25)")

        # 2. Audit View Logic (30 pts)
        vw_audit_exists = result.get('vw_audit_exists', False)
        audit_counts = result.get('audit_counts', {})
        actual_missing = audit_counts.get('missing', -1)
        actual_invalid = audit_counts.get('invalid', -1)
        
        if vw_audit_exists:
            score += 10
            feedback_parts.append("LICENSE_AUDIT_VW exists (10/10)")
            
            if actual_missing == expected_missing:
                score += 10
                feedback_parts.append(f"Correct MISSING_SUSPENSION count: {actual_missing} (10/10)")
            else:
                feedback_parts.append(f"Incorrect MISSING_SUSPENSION count: got {actual_missing}, expected {expected_missing} (0/10)")
                
            if actual_invalid == expected_invalid:
                score += 10
                feedback_parts.append(f"Correct INVALID_SUSPENSION count: {actual_invalid} (10/10)")
            else:
                feedback_parts.append(f"Incorrect INVALID_SUSPENSION count: got {actual_invalid}, expected {expected_invalid} (0/10)")
        else:
            feedback_parts.append("LICENSE_AUDIT_VW missing (0/30)")

        # 3. Materialized Summary (15 pts)
        mv_summary_exists = result.get('mv_summary_exists', False)
        mv_counts = result.get('mv_counts', {})
        
        if mv_summary_exists:
            score += 5
            feedback_parts.append("AUDIT_SUMMARY_MV exists (5/5)")
            
            # Since MV count logic returns sums of cnt, a missing group returns 0 via the union fallback.
            # If the actual view counts match the MV counts, the rollup is correct.
            # But only award if the views actually produced data.
            if actual_missing > 0 and mv_counts.get('missing', -1) == actual_missing and mv_counts.get('invalid', -1) == actual_invalid:
                score += 10
                feedback_parts.append("MV aggregations match audit view logic (10/10)")
            else:
                feedback_parts.append("MV aggregations do not match underlying views or views are empty (0/10)")
        else:
            feedback_parts.append("AUDIT_SUMMARY_MV missing (0/15)")

        # 4. Data Export (15 pts)
        csv = result.get('csv_export', {})
        if csv.get('exists') and csv.get('modified_during_task'):
            score += 5
            feedback_parts.append("CSV export created/modified (5/5)")
            
            if csv.get('size_bytes', 0) > 50 and csv.get('has_missing_records'):
                score += 5
                feedback_parts.append("CSV contains appropriate flagged records (5/5)")
            else:
                feedback_parts.append("CSV is empty or missing flagged records (0/5)")
                
            if not csv.get('has_ok_records') and csv.get('size_bytes', 0) > 0:
                score += 5
                feedback_parts.append("CSV correctly filtered out 'OK' records (5/5)")
            else:
                feedback_parts.append("CSV improperly contains 'OK' records (0/5)")
        else:
            feedback_parts.append("CSV export missing or stale (0/15)")

        # 5. GUI Evidence (15 pts)
        gui_evidence = result.get('gui_evidence', {})
        history_cnt = gui_evidence.get('sql_history_count', 0)
        mru_cnt = gui_evidence.get('mru_connection_count', 0)
        sessions_cnt = gui_evidence.get('sqldev_oracle_sessions', 0)
        
        if history_cnt > 0 or mru_cnt > 0 or sessions_cnt > 0:
            score += 15
            feedback_parts.append(f"SQL Developer UI usage verified [hist:{history_cnt}, mru:{mru_cnt}, ses:{sessions_cnt}] (15/15)")
        else:
            feedback_parts.append("No evidence of SQL Developer UI usage (0/15)")

        passed = score >= 70 and vw_rolling_exists and vw_audit_exists
        
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
            "feedback": f"Verification failed with internal error: {e}"
        }