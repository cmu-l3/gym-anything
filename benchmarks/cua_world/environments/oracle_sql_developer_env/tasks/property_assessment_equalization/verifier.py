#!/usr/bin/env python3
"""Verifier for Property Assessment Equalization task."""

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


def verify_property_assessment_equalization(traj, env_info, task_info):
    """
    Verify property assessment equalization task.

    Scoring (100 pts total):
    1. Ratio Study View (20 pts):
       - ratio_study_vw_exists -> 10 pts
       - window_func_used -> 10 pts
    2. Equalization Factors Table (20 pts):
       - equalization_factors_exists -> 10 pts
       - factors_correct -> 5 pts
       - factors_applied_status -> 5 pts
    3. Equalization Applied (20 pts):
       - assessments_updated -> 12 pts
       - merge_used -> 8 pts
    4. Advanced Analytical Views (20 pts):
       - unpivot_vw_exists -> 5 pts
       - unpivot_used -> 5 pts
       - listagg_vw_exists -> 5 pts
       - listagg_used -> 5 pts
    5. CSV Export (10 pts):
       - csv_exists & csv_size > 0 -> 10 pts
    6. GUI Usage (10 pts):
       - 2+ signals -> 10 pts

    Pass threshold: 60 pts AND equalization_factors_exists AND assessments_updated
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/equalization_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Read fields
        ratio_study_vw_exists = result.get('ratio_study_vw_exists', False)
        window_func_used = result.get('window_func_used', False)
        equalization_factors_exists = result.get('equalization_factors_exists', False)
        factors_correct = result.get('factors_correct', False)
        factors_applied_status = result.get('factors_applied_status', False)
        merge_used = result.get('merge_used', False)
        assessments_updated = result.get('assessments_updated', False)
        unpivot_vw_exists = result.get('unpivot_vw_exists', False)
        unpivot_used = result.get('unpivot_used', False)
        listagg_vw_exists = result.get('listagg_vw_exists', False)
        listagg_used = result.get('listagg_used', False)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        
        # GUI evidence
        gui_evidence = {k: v for k, v in result.items() if k in 
                        ['sql_history_count', 'mru_connection_count', 'sqldev_oracle_sessions', 'window_title_changed']}
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)

        # 1. Ratio Study View (20 pts)
        if ratio_study_vw_exists:
            score += 10
            feedback_parts.append("RATIO_STUDY_VW created (10/10)")
            if window_func_used:
                score += 10
                feedback_parts.append("Window functions used in view (10/10)")
            else:
                feedback_parts.append("Window functions not found in view text (0/10)")
        else:
            feedback_parts.append("RATIO_STUDY_VW missing (0/20)")

        # 2. Equalization Factors Table (20 pts)
        if equalization_factors_exists:
            score += 10
            feedback_parts.append("EQUALIZATION_FACTORS table exists (10/10)")
            if factors_correct:
                score += 5
                feedback_parts.append("Factor calculation is correct (5/5)")
            else:
                feedback_parts.append("Factor calculation missing or incorrect (0/5)")
                
            if factors_applied_status:
                score += 5
                feedback_parts.append("Status updated to APPLIED (5/5)")
            else:
                feedback_parts.append("Status not set to APPLIED (0/5)")
        else:
            feedback_parts.append("EQUALIZATION_FACTORS table missing (0/20)")

        # 3. Equalization Applied (20 pts)
        if assessments_updated:
            score += 12
            feedback_parts.append("Assessments successfully updated (12/12)")
            if merge_used:
                score += 8
                feedback_parts.append("MERGE statement used (8/8)")
            else:
                feedback_parts.append("UPDATE used instead of MERGE (0/8)")
        else:
            feedback_parts.append("Assessments not updated (0/20)")

        # 4. Advanced Views (20 pts)
        if unpivot_vw_exists:
            score += 5
            if unpivot_used:
                score += 5
                feedback_parts.append("UNPIVOT view created correctly (10/10)")
            else:
                feedback_parts.append("UNPIVOT keyword missing in view (5/10)")
        else:
            feedback_parts.append("PROPERTY_CHARS_UNPIVOT_VW missing (0/10)")

        if listagg_vw_exists:
            score += 5
            if listagg_used:
                score += 5
                feedback_parts.append("LISTAGG view created correctly (10/10)")
            else:
                feedback_parts.append("LISTAGG keyword missing in view (5/10)")
        else:
            feedback_parts.append("PARCEL_TAX_SUMMARY_VW missing (0/10)")

        # 5. CSV Export (10 pts)
        if csv_exists and csv_size > 50:
            score += 10
            feedback_parts.append("CSV report exported (10/10)")
        elif csv_exists:
            score += 5
            feedback_parts.append("CSV file is empty (5/10)")
        else:
            feedback_parts.append("CSV report missing (0/10)")

        # 6. GUI Usage (10 pts)
        if gui_used:
            score += 10
            feedback_parts.append(f"SQL Developer GUI used [{gui_details}] (10/10)")
        else:
            feedback_parts.append("No evidence of GUI usage (0/10)")

        # Determine pass/fail
        key_criteria = equalization_factors_exists and assessments_updated
        passed = score >= 60 and key_criteria

        if not passed and score >= 60:
            feedback_parts.append("FAILED: Core task requirements not met (missing factors table or assessments not updated)")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification script error: {str(e)}"
        }