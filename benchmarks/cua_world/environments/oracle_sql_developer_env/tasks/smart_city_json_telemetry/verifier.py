#!/usr/bin/env python3
"""Verifier for Smart City JSON Telemetry task."""

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


def verify_smart_city_json_telemetry(traj, env_info, task_info):
    """
    Verify Smart City JSON Telemetry task completion.

    Scoring (100 pts total):
    1. IS JSON Constraint (10 pts)
    2. METER_EVENTS Extraction (20 pts):
       - Table exists -> 10 pts
       - Correct row count (30) -> 10 pts
    3. PAYMENT_RECONCILIATION_VW (25 pts):
       - View exists -> 10 pts
       - Correct discrepancy row count (5) -> 15 pts
    4. MAINTENANCE_DISPATCH (25 pts):
       - Table exists -> 10 pts
       - Correct fault row count (8) -> 15 pts
    5. CSV Export (10 pts):
       - CSV exists and size > 50 bytes
    6. GUI Usage (10 pts):
       - 2+ signals for full points

    Pass threshold: 70 pts AND (payment discrepancy logic OR maintenance array flattening succeeded)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/json_telemetry_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Extract result fields
        is_json_constraint = result.get('is_json_constraint', False)
        meter_events_exists = result.get('meter_events_exists', False)
        meter_events_count = result.get('meter_events_count', 0)
        payment_vw_exists = result.get('payment_vw_exists', False)
        payment_vw_count = result.get('payment_vw_count', 0)
        dispatch_exists = result.get('dispatch_exists', False)
        dispatch_count = result.get('dispatch_count', 0)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: IS JSON Constraint (10 pts)
        if is_json_constraint:
            score += 10
            feedback_parts.append("IS JSON constraint active (10/10)")
            subscores['constraint'] = True
        else:
            feedback_parts.append("IS JSON constraint missing (0/10)")
            subscores['constraint'] = False

        # Criterion 2: METER_EVENTS (20 pts)
        if meter_events_exists:
            score += 10
            if meter_events_count == 30:
                score += 10
                feedback_parts.append("METER_EVENTS correctly extracted 30 rows (20/20)")
            elif meter_events_count > 0:
                score += 5
                feedback_parts.append(f"METER_EVENTS has incorrect row count ({meter_events_count}/30) (15/20)")
            else:
                feedback_parts.append("METER_EVENTS is empty (10/20)")
        else:
            feedback_parts.append("METER_EVENTS missing (0/20)")

        # Criterion 3: PAYMENT_RECONCILIATION_VW (25 pts)
        payment_success = False
        if payment_vw_exists:
            score += 10
            if payment_vw_count == 5:
                score += 15
                payment_success = True
                feedback_parts.append("PAYMENT_RECONCILIATION_VW correctly identified 5 discrepancies (25/25)")
            else:
                feedback_parts.append(f"PAYMENT_RECONCILIATION_VW has incorrect discrepancy count: {payment_vw_count} (10/25)")
        else:
            feedback_parts.append("PAYMENT_RECONCILIATION_VW missing (0/25)")

        # Criterion 4: MAINTENANCE_DISPATCH (25 pts)
        dispatch_success = False
        if dispatch_exists:
            score += 10
            if dispatch_count == 8:
                score += 15
                dispatch_success = True
                feedback_parts.append("MAINTENANCE_DISPATCH correctly flattened 8 hardware faults (25/25)")
            else:
                feedback_parts.append(f"MAINTENANCE_DISPATCH has incorrect fault count: {dispatch_count} (10/25)")
        else:
            feedback_parts.append("MAINTENANCE_DISPATCH missing (0/25)")

        # Criterion 5: CSV Export (10 pts)
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append("CSV exported successfully (10/10)")
            subscores['csv_export'] = True
        elif csv_exists:
            score += 5
            feedback_parts.append("CSV exported but seems empty or too small (5/10)")
            subscores['csv_export'] = False
        else:
            feedback_parts.append("CSV export missing (0/10)")
            subscores['csv_export'] = False

        # Criterion 6: GUI Usage (10 pts)
        gui_used, gui_score_ratio, gui_details = _check_gui_usage(gui_evidence)
        gui_points = int(10 * gui_score_ratio)
        score += gui_points
        if gui_used:
            feedback_parts.append(f"GUI usage verified [{gui_details}] ({gui_points}/10)")
        else:
            feedback_parts.append(f"Insufficient GUI usage evidence [{gui_details}] ({gui_points}/10)")

        # Pass logic
        # Must score >= 70 AND successfully complete at least one complex JSON array extraction task
        passed = score >= 70 and (payment_success or dispatch_success)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}"
        }