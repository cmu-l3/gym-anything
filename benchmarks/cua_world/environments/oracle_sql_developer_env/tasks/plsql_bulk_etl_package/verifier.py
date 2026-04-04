#!/usr/bin/env python3
"""Verifier for plsql_bulk_etl_package."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/plsql_bulk_etl_package_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _check_gui_usage(gui_evidence):
    signals = 0
    if gui_evidence.get("mru_connection_count", 0) > 0:
        signals += 1
    if gui_evidence.get("sqldev_oracle_sessions", 0) > 0:
        signals += 1
    if gui_evidence.get("sql_history_count", 0) > 0:
        signals += 1
    return signals >= 2, signals


def verify_plsql_bulk_etl_package(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {exc}"}

    score = 0
    feedback = []

    if result.get("package_spec_exists") and result.get("package_body_exists"):
        score += 20
        feedback.append("Package specification and body exist.")
    else:
        feedback.append("Package specification/body missing.")

    logic_flags = [
        ("bulk_collect_found", "BULK COLLECT"),
        ("autonomous_transaction_found", "PRAGMA AUTONOMOUS_TRANSACTION"),
        ("ref_cursor_found", "REF CURSOR"),
        ("process_reviews_found", "PROCESS_REVIEWS"),
        ("get_unprocessed_found", "GET_UNPROCESSED"),
    ]
    logic_score = 0
    for key, label in logic_flags:
        if result.get(key):
            logic_score += 6
        else:
            feedback.append(f"Missing package logic: {label}.")
    score += logic_score
    if logic_score:
        feedback.append(f"Package implementation signals: {logic_score}/30.")

    total_reviews = int(result.get("total_reviews", 0))
    processed_reviews = int(result.get("processed_reviews", 0))
    new_reviews = int(result.get("new_reviews", 0))
    if total_reviews >= 12000 and processed_reviews == total_reviews and new_reviews == 0:
        score += 25
        feedback.append("All review rows were processed.")
    elif processed_reviews > 0:
        partial = int(25 * processed_reviews / max(total_reviews, 1))
        score += partial
        feedback.append(f"Only {processed_reviews}/{total_reviews} reviews were processed.")
    else:
        feedback.append("No review rows were processed.")

    if int(result.get("log_rows", 0)) > 0:
        score += 10
        feedback.append("ETL log entries were written.")
    else:
        feedback.append("ETL log table is empty.")

    if result.get("view_exists") and int(result.get("view_rows", 0)) > 0:
        score += 10
        feedback.append("Summary view exists and returns rows.")
    elif result.get("view_exists"):
        score += 5
        feedback.append("Summary view exists but returned no rows.")
    else:
        feedback.append("Summary view missing.")

    if result.get("csv_exists") and result.get("csv_is_new") and int(result.get("csv_line_count", 0)) > 1:
        score += 10
        feedback.append("CSV export exists and was created during the task.")
    elif result.get("csv_exists"):
        score += 4
        feedback.append("CSV export exists but timestamp/content checks were weak.")
    else:
        feedback.append("CSV export missing.")

    gui_used, gui_signals = _check_gui_usage(result.get("gui_evidence", {}))
    if gui_used:
        score += 5
        feedback.append("GUI usage signals detected in SQL Developer.")
    else:
        feedback.append(f"Limited GUI evidence ({gui_signals}/3 signals).")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " ".join(feedback)}
