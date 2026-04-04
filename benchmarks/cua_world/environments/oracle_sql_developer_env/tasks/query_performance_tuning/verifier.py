#!/usr/bin/env python3
"""Verifier for Query Performance Tuning task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
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


def verify_query_performance_tuning(traj, env_info, task_info):
    """
    Verify query performance tuning task completion.

    Scoring (100 pts total):
    1. Indexes created on required columns of PERFORMANCE_ORDERS (35 pts)
       - ORDER_AMOUNT index: 12 pts
       - ORDER_DATE index: 12 pts
       - CUSTOMER_ID index: 11 pts
    2. Tuning report file exists with content (20 pts)
    3. Report demonstrates explain plan analysis (20 pts)
    4. GUI usage verified (25 pts)

    Pass threshold: 60 pts
    Agent must create at least 3 required indexes to pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/query_perf_tuning_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        total_idx = result.get('total_indexes_on_performance_orders', 0)
        idx_amount = result.get('idx_order_amount', False)
        idx_date = result.get('idx_order_date', False)
        idx_customer = result.get('idx_customer_id', False)
        idx_salesperson = result.get('idx_salesperson_id', False)
        idx_dept = result.get('idx_customer_dept', False)
        initial_idx = result.get('initial_index_count', 0)
        report_exists = result.get('tuning_report_exists', False)
        report_size = result.get('tuning_report_size', 0)
        report_explain = result.get('report_mentions_explain', False)
        report_index = result.get('report_mentions_index', False)
        report_fullscan = result.get('report_mentions_fullscan', False)
        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: Index creation (35 pts)
        required_created = []
        optional_created = []

        if idx_amount:
            score += 12
            required_created.append("ORDER_AMOUNT")
        if idx_date:
            score += 12
            required_created.append("ORDER_DATE")
        if idx_customer:
            score += 11
            required_created.append("CUSTOMER_ID")
        if idx_salesperson:
            score += 3
            optional_created.append("SALESPERSON_ID")
        if idx_dept:
            score += 3
            optional_created.append("CUSTOMER_DEPT_ID")

        # Cap index score at 35
        index_score = (12 if idx_amount else 0) + (12 if idx_date else 0) + (11 if idx_customer else 0)
        bonus_index = (3 if idx_salesperson else 0) + (3 if idx_dept else 0)
        index_score_total = min(index_score + bonus_index, 35)

        # Recalculate score without overcounting
        score = 0
        score += index_score_total

        all_required = idx_amount and idx_date and idx_customer
        subscores['indexes'] = all_required

        newly_created = total_idx > initial_idx
        if required_created or optional_created:
            msg = f"Indexes created on: {', '.join(required_created + optional_created)} ({index_score_total}/35)"
            feedback_parts.append(msg)
        else:
            feedback_parts.append(f"No indexes created on PERFORMANCE_ORDERS (0/35)")

        # Criterion 2: Tuning report (20 pts)
        if report_exists and report_size > 300:
            score += 20
            feedback_parts.append(f"tuning_report.txt exists ({report_size} bytes) (20/20)")
            subscores['report'] = True
        elif report_exists and report_size > 50:
            score += 10
            feedback_parts.append(f"tuning_report.txt exists but thin ({report_size} bytes) (10/20)")
            subscores['report'] = False
        else:
            feedback_parts.append("tuning_report.txt not found or empty (0/20)")
            subscores['report'] = False

        # Criterion 3: Report quality — explain plan evidence (20 pts)
        quality_pts = 0
        quality_details = []
        if report_explain:
            quality_pts += 10
            quality_details.append("mentions explain plan")
        if report_index:
            quality_pts += 5
            quality_details.append("mentions indexes")
        if report_fullscan:
            quality_pts += 5
            quality_details.append("identifies full scans")
        score += quality_pts
        subscores['report_quality'] = quality_pts >= 10
        if quality_pts > 0:
            feedback_parts.append(f"Report quality: {', '.join(quality_details)} ({quality_pts}/20)")
        else:
            feedback_parts.append("Report lacks explain plan / performance analysis content (0/20)")

        # Criterion 4: GUI usage (25 pts)
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 25)
        score += gui_pts
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details}) ({gui_pts}/25)")
        else:
            feedback_parts.append(f"GUI evidence: {gui_details} ({gui_pts}/25)")

        # VLM bonus
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there an Explain Plan tab or execution plan visible with operations like "
                        "TABLE ACCESS, INDEX RANGE SCAN, or similar? Or is there SQL code for CREATE INDEX? "
                        "Reply VERIFIED if performance tuning work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: explain plan / index work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        passed = (
            all_required and
            subscores.get('report', False) and
            score >= 60
        )

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
