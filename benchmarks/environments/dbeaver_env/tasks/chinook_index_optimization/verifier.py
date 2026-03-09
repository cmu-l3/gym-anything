#!/usr/bin/env python3
"""
Verifier for chinook_index_optimization task.

Scoring (100 points):
- DBeaver 'Chinook' connection exists: 10 pts
- ≥3 new indexes created: 30 pts (10 per index, up to 3)
- Indexes cover both tracks and invoices tables: 25 pts
- index_report.txt exists at correct path with sufficient content: 20 pts
- Report mentions all 3 query optimization contexts: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

REPORT_PATH = "/home/ga/Documents/reports/index_report.txt"


def verify_chinook_index_optimization(traj, env_info, task_info):
    """Verify Chinook index optimization task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/chinook_index_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: DBeaver 'Chinook' connection (10 pts) ---
    if result.get("chinook_conn_found"):
        score += 10
        subscores["connection"] = 10
        feedback.append("'Chinook' DBeaver connection found")
    else:
        subscores["connection"] = 0
        feedback.append("MISSING: DBeaver 'Chinook' connection not found")

    # --- Criterion 2: ≥3 new indexes created (30 pts) ---
    new_index_count = result.get("new_index_count", 0)

    if new_index_count >= 3:
        score += 30
        subscores["indexes_created"] = 30
        feedback.append(f"{new_index_count} new indexes created (meets ≥3 requirement)")
    elif new_index_count == 2:
        score += 20
        subscores["indexes_created"] = 20
        feedback.append(f"2 new indexes created (need ≥3)")
    elif new_index_count == 1:
        score += 10
        subscores["indexes_created"] = 10
        feedback.append(f"1 new index created (need ≥3)")
    else:
        subscores["indexes_created"] = 0
        feedback.append("No new indexes created")

    # --- Criterion 3: Indexes cover correct tables (25 pts) ---
    has_tracks = result.get("has_tracks_index", False)
    has_invoices = result.get("has_invoices_index", False)
    has_ms = result.get("has_milliseconds_index", False)
    has_date = result.get("has_date_index", False)
    has_composer = result.get("has_composer_index", False)

    table_coverage_score = 0
    if has_tracks and has_invoices:
        table_coverage_score += 15
        feedback.append("Indexes cover both 'tracks' and 'invoices' tables")
    elif has_tracks:
        table_coverage_score += 8
        feedback.append("Indexes cover 'tracks' table (missing invoices index)")
    elif has_invoices:
        table_coverage_score += 7
        feedback.append("Indexes cover 'invoices' table (missing tracks index)")
    else:
        feedback.append("MISSING: No indexes on expected tables (tracks, invoices)")

    column_coverage_score = 0
    cols_covered = []
    if has_ms or has_date:
        column_coverage_score += 5
        if has_ms:
            cols_covered.append("Milliseconds")
        if has_date:
            cols_covered.append("InvoiceDate")
    if has_composer:
        column_coverage_score += 5
        cols_covered.append("Composer")

    if cols_covered:
        feedback.append(f"Index columns covered: {', '.join(cols_covered)}")

    table_score = table_coverage_score + column_coverage_score
    score += table_score
    subscores["table_coverage"] = table_score

    # --- Criterion 4: Report exists with content (20 pts) ---
    if result.get("report_exists"):
        report_size = result.get("report_size", 0)
        has_index_names = result.get("report_has_index_names", False)

        if report_size >= 500 and has_index_names:
            score += 20
            subscores["report"] = 20
            feedback.append(f"index_report.txt has substantial content ({report_size} bytes) with index names")
        elif report_size >= 200:
            score += 13
            subscores["report"] = 13
            feedback.append(f"index_report.txt exists with some content ({report_size} bytes)")
        elif report_size >= 50:
            score += 7
            subscores["report"] = 7
            feedback.append(f"index_report.txt exists but minimal ({report_size} bytes)")
        else:
            score += 3
            subscores["report"] = 3
            feedback.append("index_report.txt exists but essentially empty")

        if not result.get("report_created_after_start"):
            feedback.append("Warning: report may be pre-existing")
    else:
        subscores["report"] = 0
        feedback.append(f"MISSING: index_report.txt not found at {REPORT_PATH}")

    # --- Criterion 5: Report mentions all 3 query contexts (15 pts) ---
    has_qa = result.get("report_has_query_a", False)
    has_qb = result.get("report_has_query_b", False)
    has_qc = result.get("report_has_query_c", False)
    queries_covered = sum([has_qa, has_qb, has_qc])

    if queries_covered == 3:
        score += 15
        subscores["report_coverage"] = 15
        feedback.append("Report covers all 3 query optimization contexts")
    elif queries_covered == 2:
        score += 10
        subscores["report_coverage"] = 10
        feedback.append(f"Report covers 2/3 query optimization contexts")
    elif queries_covered == 1:
        score += 5
        subscores["report_coverage"] = 5
        feedback.append(f"Report covers 1/3 query optimization contexts")
    else:
        subscores["report_coverage"] = 0
        if result.get("report_exists"):
            feedback.append("Report does not mention any of the 3 query optimization contexts")
        else:
            feedback.append("Report missing — query coverage check skipped")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "new_index_count": new_index_count,
            "new_indexes": result.get("new_indexes", ""),
            "has_tracks_index": has_tracks,
            "has_invoices_index": has_invoices,
            "report_size": result.get("report_size", 0),
            "queries_covered": queries_covered
        }
    }
