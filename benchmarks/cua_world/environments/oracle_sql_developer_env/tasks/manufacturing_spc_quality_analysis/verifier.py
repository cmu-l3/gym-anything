#!/usr/bin/env python3
"""Verifier for Manufacturing SPC Quality Analysis task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used."""
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


def verify_manufacturing_spc_quality_analysis(traj, env_info, task_info):
    """
    Verify manufacturing SPC quality analysis task completion.

    Scoring (100 pts total):
    1. Process Capability View (20 pts)
       - Exists (10)
       - Uses Analytics (5)
       - Cpk successfully computed (5)
    2. Control Violations (25 pts)
       - Table exists (5)
       - Procedure exists (10)
       - Violations populated (5)
       - Multiple rules detected (5)
    3. Defect Pareto & Calibration (12 pts)
       - Pareto view exists (4)
       - Pareto uses Window (4)
       - Calibration alerts view (4)
    4. Quality Audit Summary MV (15 pts)
       - MV exists (10)
       - Uses ROLLUP/CUBE (5)
    5. CSV Export (20 pts)
       - CSV exists and size > 100 (10)
       - CSV has expected data keywords (10)
    6. GUI Usage (8 pts)
       - 2+ signals (8)

    Pass threshold: 60 pts AND Capability View Exists AND Control Violations Exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/spc_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Extract variables
        process_capability_vw_exists = result.get('process_capability_vw_exists', False)
        process_capability_analytics = result.get('process_capability_analytics', False)
        cpk_computed = result.get('cpk_computed', False)
        
        control_violations_exists = result.get('control_violations_exists', False)
        detect_proc_exists = result.get('detect_proc_exists', False)
        violations_populated = result.get('violations_populated', 0)
        multiple_rules_detected = result.get('multiple_rules_detected', 0)
        
        defect_pareto_exists = result.get('defect_pareto_exists', False)
        pareto_window_used = result.get('pareto_window_used', False)
        
        calibration_alerts_exists = result.get('calibration_alerts_exists', False)
        
        quality_audit_mv_exists = result.get('quality_audit_mv_exists', False)
        audit_rollup_used = result.get('audit_rollup_used', False)
        
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        csv_has_data = result.get('csv_has_data', False)
        
        gui_evidence = result.get('gui_evidence', {})

        # 1. Process Capability
        if process_capability_vw_exists:
            score += 10
            feedback_parts.append("Capability View exists (10/10)")
            if process_capability_analytics:
                score += 5
                feedback_parts.append("Analytics used in Capability (5/5)")
            if cpk_computed:
                score += 5
                feedback_parts.append("Cpk values computed (5/5)")
        else:
            feedback_parts.append("Capability View missing (0/20)")

        # 2. Control Violations
        if control_violations_exists:
            score += 5
            feedback_parts.append("Violations table exists (5/5)")
            if violations_populated > 0:
                score += 5
                feedback_parts.append(f"Violations populated: {violations_populated} (5/5)")
            if multiple_rules_detected > 1:
                score += 5
                feedback_parts.append(f"Multiple rules detected: {multiple_rules_detected} (5/5)")
        else:
            feedback_parts.append("Violations table missing (0/15)")

        if detect_proc_exists:
            score += 10
            feedback_parts.append("Detection Procedure exists (10/10)")
        else:
            feedback_parts.append("Detection Procedure missing (0/10)")

        # 3. Pareto & Calibration
        if defect_pareto_exists:
            score += 4
            if pareto_window_used:
                score += 4
                feedback_parts.append("Pareto View exists w/ Window functions (8/8)")
            else:
                feedback_parts.append("Pareto View exists, no Window functions (4/8)")
                
        if calibration_alerts_exists:
            score += 4
            feedback_parts.append("Calibration Alerts exists (4/4)")

        # 4. Audit MV
        if quality_audit_mv_exists:
            score += 10
            if audit_rollup_used:
                score += 5
                feedback_parts.append("Audit MV exists w/ ROLLUP (15/15)")
            else:
                feedback_parts.append("Audit MV exists, no ROLLUP (10/15)")
        else:
            feedback_parts.append("Audit MV missing (0/15)")

        # 5. CSV Export
        if csv_exists and csv_size > 100:
            score += 10
            if csv_has_data:
                score += 10
                feedback_parts.append("Valid CSV report exported (20/20)")
            else:
                feedback_parts.append("CSV exported but missing keywords (10/20)")
        else:
            feedback_parts.append("Valid CSV report missing (0/20)")

        # 6. GUI Usage
        gui_used, gui_multiplier, gui_details = _check_gui_usage(gui_evidence)
        if gui_used:
            score += 8
            feedback_parts.append(f"GUI usage confirmed [{gui_details}] (8/8)")
        else:
            feedback_parts.append(f"Insufficient GUI usage evidence [{gui_details}] (0/8)")

        # Final evaluation
        key_criteria = process_capability_vw_exists and control_violations_exists
        passed = (score >= 60) and key_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}