#!/usr/bin/env python3
"""
Verifier for Hospital Infection Contact Tracing Task.
Uses copy_from_env to evaluate DB outputs against ground truth data.
"""

import json
import os
import tempfile
import logging

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


def verify_hospital_infection_contact_tracing(traj, env_info, task_info):
    """
    Verify the contact tracing implementation.
    
    Scoring (100 pts total):
    1. INDEX_INFECTIONS_VW (15 pts):
       - View exists (5 pts)
       - Contains exact expected row count (2 rows) (10 pts)
    2. PATIENT_EXPOSURES_VW (35 pts):
       - View exists (10 pts)
       - Calculates overlap >= 12h accurately: exposed subjects should be 200, 202, 400 (25 pts)
         (If count is close or overlaps slightly wrong, partial credit)
    3. WARD_HOTSPOT_MV (15 pts):
       - View exists (15 pts)
    4. ISOLATION_ORDERS and Procedure (25 pts):
       - ISOLATION_ORDERS table exists (5 pts)
       - PROC_FLAG_ISOLATION exists (5 pts)
       - Table contains isolated patients (currently admitted only): subjects 200, 400 (15 pts)
    5. GUI Usage (10 pts):
       - SQL Developer used
    
    Pass threshold: 70 pts AND Exposures View successfully filters >= 12h logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/infection_tracing_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        index_vw_exists = result.get('index_vw_exists', False)
        index_rows = result.get('index_rows', 0)
        exposures_vw_exists = result.get('exposures_vw_exists', False)
        exposed_subjects = str(result.get('exposed_subjects', ''))
        hotspot_mv_exists = result.get('hotspot_mv_exists', False)
        isolation_orders_exists = result.get('isolation_orders_exists', False)
        isolated_subjects = str(result.get('isolated_subjects', ''))
        proc_exists = result.get('proc_exists', False)
        
        gui_used, _, gui_details = _check_gui_usage(result)

        # 1. INDEX_INFECTIONS_VW (15 pts)
        if index_vw_exists:
            score += 5
            if index_rows == 2:
                score += 10
                feedback_parts.append("Index infections view correct (15/15)")
            else:
                feedback_parts.append(f"Index infections view exists but has {index_rows} rows instead of 2 (5/15)")
        else:
            feedback_parts.append("Index infections view missing (0/15)")

        # 2. PATIENT_EXPOSURES_VW (35 pts)
        exposures_correct = False
        if exposures_vw_exists:
            score += 10
            # Ground truth exposed subjects: 200, 202, 400
            # Note: The order from LISTAGG is sorted ascending
            if "200" in exposed_subjects and "400" in exposed_subjects and "201" not in exposed_subjects:
                if "202" in exposed_subjects:
                    score += 25
                    exposures_correct = True
                    feedback_parts.append("Patient exposures overlap logic correct (35/35)")
                else:
                    score += 15
                    feedback_parts.append(f"Patient exposures partially correct, missing some cases. Found: {exposed_subjects} (25/35)")
            else:
                feedback_parts.append(f"Patient exposures overlap logic incorrect. Found: {exposed_subjects} (10/35)")
        else:
            feedback_parts.append("Patient exposures view missing (0/35)")

        # 3. WARD_HOTSPOT_MV (15 pts)
        if hotspot_mv_exists:
            score += 15
            feedback_parts.append("Hotspot MV exists (15/15)")
        else:
            feedback_parts.append("Hotspot MV missing (0/15)")

        # 4. ISOLATION ORDERS (25 pts)
        if isolation_orders_exists:
            score += 5
            if proc_exists:
                score += 5
            
            # Ground truth isolated subjects (currently admitted exposures): 200, 400
            if "200" in isolated_subjects and "400" in isolated_subjects and "202" not in isolated_subjects:
                score += 15
                feedback_parts.append("Isolation orders correctly applied to admitted patients (25/25)")
            elif "200" in isolated_subjects or "400" in isolated_subjects:
                score += 5
                feedback_parts.append(f"Isolation orders partially correct. Found: {isolated_subjects} (15/25)")
            else:
                feedback_parts.append(f"Isolation orders missing expected patients. Found: {isolated_subjects} (10/25)")
        else:
            feedback_parts.append("Isolation orders table missing (0/25)")

        # 5. GUI Usage (10 pts)
        if gui_used:
            score += 10
            feedback_parts.append(f"GUI usage detected [{gui_details}] (10/10)")
        else:
            feedback_parts.append(f"No GUI usage detected [{gui_details}] (0/10)")

        passed = score >= 70 and exposures_correct

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}