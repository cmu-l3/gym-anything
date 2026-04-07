#!/usr/bin/env python3
"""Verifier for Insurance Claims Fraud Detection task."""

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


def verify_insurance_claims_fraud_detection(traj, env_info, task_info):
    """
    Verify insurance claims fraud detection task completion.

    Scoring (100 pts total):
    1. FRAUD_DETECTION_PKG Package (25 pts)
       - package_exists AND package_body_valid -> 10 pts
       - benford_function_exists -> 5 pts (bonus: pipelined_used -> +3 pts)
       - outlier_function_exists -> 4 pts
       - duplicate_proc_exists -> 3 pts
       - upcoding_proc_exists -> 3 pts (cap at 25)
    2. Fraud Detection Results (35 pts)
       - fraud_flags_table_exists -> 5 pts
       - fraud_flags_count > 0 -> 5 pts
       - benford_flags > 0 -> 7 pts
       - outlier_flags > 0 -> 6 pts
       - duplicate_flags > 0 -> 6 pts
       - upcoding_flags > 0 -> 3 pts
       - temporal_flags > 0 -> 3 pts
    3. Reporting (20 pts)
       - fraud_summary_mv_exists -> 8 pts
       - csv_exists AND csv_size > 50 -> 7 pts
       - csv_has_flag_types -> 5 pts
    4. GUI Usage (10 pts)
       - 2+ signals -> full points
    5. Advanced Features Bonus (10 pts)
       - pipelined_used -> 5 pts
       - object_type_count > 0 -> 5 pts

    Pass threshold: 70 pts
    Pass conditions: score >= 70 AND package_exists AND fraud_flags_count > 0
                     AND at least 2 fraud types detected
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/claims_fraud_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Extract result fields
        package_exists = result.get('package_exists', False)
        package_body_valid = result.get('package_body_valid', False)
        benford_function_exists = result.get('benford_function_exists', False)
        pipelined_used = result.get('pipelined_used', False)
        outlier_function_exists = result.get('outlier_function_exists', False)
        duplicate_proc_exists = result.get('duplicate_proc_exists', False)
        upcoding_proc_exists = result.get('upcoding_proc_exists', False)
        fraud_flags_table_exists = result.get('fraud_flags_table_exists', False)
        fraud_flags_count = result.get('fraud_flags_count', 0)
        benford_flags = result.get('benford_flags', 0)
        outlier_flags = result.get('outlier_flags', 0)
        duplicate_flags = result.get('duplicate_flags', 0)
        upcoding_flags = result.get('upcoding_flags', 0)
        temporal_flags = result.get('temporal_flags', 0)
        fraud_summary_mv_exists = result.get('fraud_summary_mv_exists', False)
        object_type_count = result.get('object_type_count', 0)
        csv_exists = result.get('csv_exists', False)
        csv_size = result.get('csv_size', 0)
        csv_has_flag_types = result.get('csv_has_flag_types', False)
        gui_evidence = result.get('gui_evidence', {})

        # -----------------------------------------------------------
        # Criterion 1: FRAUD_DETECTION_PKG Package (25 pts)
        # -----------------------------------------------------------
        pkg_score = 0
        pkg_details = []

        if package_exists and package_body_valid:
            pkg_score += 10
            pkg_details.append("package+body valid")
        elif package_exists:
            pkg_score += 5
            pkg_details.append("package spec only (body invalid)")

        if benford_function_exists:
            pkg_score += 5
            pkg_details.append("Benford function")
            if pipelined_used:
                pkg_score += 3
                pkg_details.append("pipelined")

        if outlier_function_exists:
            pkg_score += 4
            pkg_details.append("outlier function")

        if duplicate_proc_exists:
            pkg_score += 3
            pkg_details.append("duplicate proc")

        if upcoding_proc_exists:
            pkg_score += 3
            pkg_details.append("upcoding proc")

        pkg_score = min(pkg_score, 25)
        score += pkg_score
        subscores['package'] = package_exists
        if pkg_details:
            feedback_parts.append(f"Package: {', '.join(pkg_details)} ({pkg_score}/25)")
        else:
            feedback_parts.append("FRAUD_DETECTION_PKG not found (0/25)")

        # -----------------------------------------------------------
        # Criterion 2: Fraud Detection Results (35 pts)
        # -----------------------------------------------------------
        results_score = 0
        results_details = []

        if fraud_flags_table_exists:
            results_score += 5
            results_details.append("flags table exists")

        if fraud_flags_count > 0:
            results_score += 5
            results_details.append(f"{fraud_flags_count} total flags")

        if benford_flags > 0:
            results_score += 7
            results_details.append(f"Benford:{benford_flags}")

        if outlier_flags > 0:
            results_score += 6
            results_details.append(f"outlier:{outlier_flags}")

        if duplicate_flags > 0:
            results_score += 6
            results_details.append(f"duplicate:{duplicate_flags}")

        if upcoding_flags > 0:
            results_score += 3
            results_details.append(f"upcoding:{upcoding_flags}")

        if temporal_flags > 0:
            results_score += 3
            results_details.append(f"temporal:{temporal_flags}")

        score += results_score
        subscores['fraud_results'] = fraud_flags_count > 0
        if results_details:
            feedback_parts.append(f"Fraud results: {', '.join(results_details)} ({results_score}/35)")
        else:
            feedback_parts.append("No fraud detection results found (0/35)")

        # Count distinct fraud types detected
        fraud_types_detected = sum([
            benford_flags > 0,
            outlier_flags > 0,
            duplicate_flags > 0,
            upcoding_flags > 0,
            temporal_flags > 0,
        ])
        subscores['fraud_types_detected'] = fraud_types_detected

        # -----------------------------------------------------------
        # Criterion 3: Reporting (20 pts)
        # -----------------------------------------------------------
        report_score = 0
        report_details = []

        if fraud_summary_mv_exists:
            report_score += 8
            report_details.append("summary MV exists")

        if csv_exists and csv_size > 50:
            report_score += 7
            report_details.append(f"CSV exported ({csv_size} bytes)")

        if csv_has_flag_types:
            report_score += 5
            report_details.append("CSV includes flag types")

        score += report_score
        subscores['reporting'] = fraud_summary_mv_exists or (csv_exists and csv_size > 50)
        if report_details:
            feedback_parts.append(f"Reporting: {', '.join(report_details)} ({report_score}/20)")
        else:
            feedback_parts.append("No reporting artifacts found (0/20)")

        # -----------------------------------------------------------
        # Criterion 4: GUI Usage (10 pts)
        # -----------------------------------------------------------
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 10)
        score += gui_pts
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details}) ({gui_pts}/10)")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details}) ({gui_pts}/10)")
        else:
            feedback_parts.append("No GUI usage evidence (0/10)")

        # -----------------------------------------------------------
        # Criterion 5: Advanced Features Bonus (10 pts)
        # -----------------------------------------------------------
        bonus_score = 0
        bonus_details = []

        if pipelined_used:
            bonus_score += 5
            bonus_details.append("pipelined function")

        if object_type_count > 0:
            bonus_score += 5
            bonus_details.append(f"{object_type_count} custom type(s)")

        score += bonus_score
        subscores['advanced_bonus'] = bonus_score
        if bonus_details:
            feedback_parts.append(f"Advanced bonus: {', '.join(bonus_details)} (+{bonus_score})")

        # -----------------------------------------------------------
        # VLM check (optional bonus)
        # -----------------------------------------------------------
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there evidence of PL/SQL package code for fraud detection, "
                        "queries against insurance claims tables, or fraud analysis results? "
                        "Reply VERIFIED if fraud detection SQL work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: fraud detection work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        # -----------------------------------------------------------
        # Pass decision
        # -----------------------------------------------------------
        passed = (
            score >= 70
            and package_exists
            and fraud_flags_count > 0
            and fraud_types_detected >= 2
        )

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
