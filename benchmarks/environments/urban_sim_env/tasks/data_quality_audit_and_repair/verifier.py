#!/usr/bin/env python3
"""Verifier for data_quality_audit_and_repair task.

Scoring (100 points total):
  Gate:        do-nothing check
  Criterion 1 (20 pts): quality_report.csv exists, is new, has >= 3 distinct issue type rows
                         with required columns (issue_type, records_affected, repair_method)
  Criterion 2 (30 pts): GT-based issue detection: 7.5 pts per detected GT category
                         (physical impossibility, year impossibility, price anomaly,
                          density impossibility)
  Criterion 3 (20 pts): buildings_repaired.csv exists, is new, has >= 80% of original row count
  Criterion 4 (15 pts): chart PNG exists, is new, > 5 KB
  Criterion 5 (15 pts): notebook has >= 5 executed cells

Pass threshold: 60
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_data_quality(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env("/tmp/data_quality_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

    # Do-nothing gate
    if not result.get('report_csv_exists') and not result.get('repaired_csv_exists'):
        return {"passed": False, "score": 0, "feedback": "No output files produced (do-nothing)"}

    gt = result.get('gt', {})
    score = 0
    fb = []

    # ── Criterion 1: quality_report.csv structure ─────────────────────────
    c1 = 0
    if result.get('report_csv_exists'):
        c1 += 4
        if result.get('report_csv_is_new'):
            c1 += 4
        issue_count = result.get('issue_types_count', 0)
        min_issues = metadata.get('min_issue_types', 3)
        if issue_count >= 4:
            c1 += 6
        elif issue_count >= min_issues:
            c1 += 4
        elif issue_count >= 1:
            c1 += 1
        if result.get('report_has_issue_type'):
            c1 += 2
        if result.get('report_has_records_affected'):
            c1 += 2
        if result.get('report_has_repair_method'):
            c1 += 2
    score += c1
    fb.append(f"C1 report-structure: {c1}/20 (issue_types={result.get('issue_types_count',0)})")

    # ── Criterion 2: GT-based category detection (30 pts, 7.5 per category) ─
    c2 = 0
    categories = [
        ('found_physical_issue', 'physical impossibility (stories>15, sqft<3000)'),
        ('found_year_issue', 'year impossibility (year_built>2024)'),
        ('found_price_issue', 'price anomaly (residential with price=0)'),
        ('found_density_issue', 'density impossibility (units>800 in <5-story buildings)'),
    ]
    pts_each = 7
    found_count = 0
    for key, label in categories:
        if result.get(key):
            c2 += pts_each
            found_count += 1
    # Partial credit for finding more than expected
    if found_count == 4:
        c2 += 2  # bonus for finding all 4
    score += c2
    fb.append(f"C2 gt-detection: {c2}/30 (found {found_count}/4 GT categories)")

    # ── Criterion 3: buildings_repaired.csv ───────────────────────────────
    c3 = 0
    if result.get('repaired_csv_exists'):
        c3 += 5
        if result.get('repaired_csv_is_new'):
            c3 += 7
        repaired_rows = result.get('repaired_csv_rows', 0)
        total_gt = gt.get('total_buildings', 0)
        if total_gt > 0 and repaired_rows >= total_gt * 0.8:
            c3 += 8
        elif repaired_rows > 100:
            c3 += 3
    score += c3
    fb.append(f"C3 repaired-csv: {c3}/20 (rows={result.get('repaired_csv_rows',0)}, "
              f"gt_total={gt.get('total_buildings',0)})")

    # ── Criterion 4: Chart ────────────────────────────────────────────────
    c4 = 0
    if result.get('chart_exists'):
        c4 += 5
        if result.get('chart_is_new'):
            c4 += 5
        if result.get('chart_size_kb', 0) > 5:
            c4 += 5
    score += c4
    fb.append(f"C4 chart: {c4}/15 (size={result.get('chart_size_kb',0):.1f}KB)")

    # ── Criterion 5: Notebook executed ────────────────────────────────────
    c5 = 0
    exec_cells = result.get('notebook_executed_cells', 0)
    if exec_cells >= 6:
        c5 = 15
    elif exec_cells >= 4:
        c5 = 10
    elif exec_cells >= 2:
        c5 = 5
    elif exec_cells >= 1:
        c5 = 2
    score += c5
    fb.append(f"C5 notebook: {c5}/15 (executed_cells={exec_cells})")

    score = min(score, 100)
    passed = score >= metadata.get('pass_threshold', 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }
