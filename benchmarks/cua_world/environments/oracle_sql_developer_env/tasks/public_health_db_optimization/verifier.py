#!/usr/bin/env python3
"""Verifier for Public Health Database Optimization task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used."""
    if not gui_evidence:
        return False, "No GUI evidence"
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
    gui_used = signals >= 1
    return gui_used, "; ".join(details) or "No signals"


def verify_public_health_db_optimization(traj, env_info, task_info):
    """
    Verify public health database optimization task completion.

    Scoring (100 pts total):
    1. Virtual Column (10 pts)
       - vc_exists -> 10 pts
    2. Function-Based Index (15 pts)
       - fbi_exists AND 'UPPER' in expression -> 15 pts
    3. Materialized View Log (15 pts)
       - mlog_exists AND mlog_rowids='YES' AND mlog_seq='YES' AND mlog_new_val='YES' -> 15 pts
    4. Fast Refresh MV (20 pts)
       - mv_exists AND mv_refresh='FAST' -> 20 pts
    5. Pest View Regex (15 pts)
       - pest_view_exists -> 15 pts
    6. Chronic Offender Window Function (15 pts)
       - chronic_view_exists -> 15 pts
    7. CSV Export (5 pts)
       - csv_exists AND csv_size > 0 AND file_created_during_task -> 5 pts
    8. GUI Evidence (5 pts)
       - GUI used -> 5 pts

    Pass threshold: 75 pts AND Fast Refresh MV implemented AND Window Function implemented.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/public_health_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []

        # Read JSON fields
        vc_exists = result.get('vc_exists', False)
        fbi_exists = result.get('fbi_exists', False)
        fbi_expr = result.get('fbi_expr', '').upper()
        mlog_exists = result.get('mlog_exists', False)
        mlog_rowids = result.get('mlog_rowids', 'NO')
        mlog_seq = result.get('mlog_seq', 'NO')
        mlog_new_val = result.get('mlog_new_val', 'NO')
        mv_exists = result.get('mv_exists', False)
        mv_refresh = result.get('mv_refresh', '')
        pest_view_exists = result.get('pest_view_exists', False)
        chronic_view_exists = result.get('chronic_view_exists', False)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        file_created_during_task = result.get('file_created_during_task', False)
        gui_evidence = result.get('gui_evidence', {})

        # 1. Virtual Column (10 pts)
        if vc_exists:
            score += 10
            feedback_parts.append("Virtual column INSPECTION_YEAR exists (10/10)")
        else:
            feedback_parts.append("Virtual column missing (0/10)")

        # 2. Function-Based Index (15 pts)
        if fbi_exists and 'UPPER' in fbi_expr:
            score += 15
            feedback_parts.append("Function-Based Index with UPPER() exists (15/15)")
        elif fbi_exists:
            score += 5
            feedback_parts.append("FBI exists but expression doesn't match UPPER (5/15)")
        else:
            feedback_parts.append("Function-Based Index missing (0/15)")

        # 3. MV Log (15 pts)
        if mlog_exists:
            pts = 5
            if mlog_rowids == 'YES' and mlog_seq == 'YES':
                pts += 5
            if mlog_new_val == 'YES':
                pts += 5
            score += pts
            feedback_parts.append(f"MV Log configured (ROWIDS={mlog_rowids}, SEQ={mlog_seq}, NEW_VAL={mlog_new_val}) ({pts}/15)")
        else:
            feedback_parts.append("Materialized View Log missing (0/15)")

        # 4. Fast Refresh MV (20 pts)
        mv_success = False
        if mv_exists and mv_refresh == 'FAST':
            score += 20
            mv_success = True
            feedback_parts.append("FAST Refresh Materialized View exists (20/20)")
        elif mv_exists:
            score += 10
            feedback_parts.append(f"MV exists but refresh method is '{mv_refresh}', not FAST (10/20)")
        else:
            feedback_parts.append("Materialized View MV_ZIP_STATS missing (0/20)")

        # 5. Pest View Regex (15 pts)
        if pest_view_exists:
            score += 15
            feedback_parts.append("Pest violations view exists (15/15)")
        else:
            feedback_parts.append("Pest violations view missing (0/15)")

        # 6. Chronic Offender Window Function (15 pts)
        window_fn_success = False
        if chronic_view_exists:
            score += 15
            window_fn_success = True
            feedback_parts.append("Chronic failures analytical view exists (15/15)")
        else:
            feedback_parts.append("Chronic failures view missing (0/15)")

        # 7. CSV Export (5 pts)
        if csv_exists and csv_size > 0 and file_created_during_task:
            score += 5
            feedback_parts.append("Valid CSV export generated during task (5/5)")
        elif csv_exists:
            feedback_parts.append("CSV exists but not modified during task (0/5)")
        else:
            feedback_parts.append("CSV export missing (0/5)")

        # 8. GUI Evidence (5 pts)
        gui_used, gui_msg = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 5
            feedback_parts.append(f"SQL Developer GUI used [{gui_msg}] (5/5)")
        else:
            feedback_parts.append(f"No evidence of SQL Developer usage [{gui_msg}] (0/5)")

        # Evaluate Pass/Fail
        passed = score >= 75 and mv_success and window_fn_success

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error in verifier: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with exception: {e}"}