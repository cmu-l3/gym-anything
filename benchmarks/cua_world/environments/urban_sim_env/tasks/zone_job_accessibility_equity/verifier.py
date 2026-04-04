#!/usr/bin/env python3
"""Verifier for zone_job_accessibility_equity task.

Scoring (100 points total):
  Gate:        do-nothing check (no csv and no chart → score=0)
  Criterion 1 (20 pts): CSV exists, is new, has required columns,
                         covers ≥ 30 zones
  Criterion 2 (20 pts): equity_gap_score values numeric, all in [0,1],
                         values vary across zones (std > 0)
  Criterion 3 (20 pts): low_income_share in [0,1]; jobs_per_household ≥ 0;
                         total_jobs and total_households columns non-negative
  Criterion 4 (25 pts): Chart PNG exists, is new, > 5 KB
  Criterion 5 (15 pts): Notebook has ≥ 3 executed code cells

Pass threshold: 60
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_zone_job_equity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env("/tmp/zone_equity_result.json", tmp.name)
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
    if not result.get('csv_exists') and not result.get('chart_exists'):
        return {"passed": False, "score": 0, "feedback": "No output files produced (do-nothing)"}

    score = 0
    fb = []

    # ── Criterion 1: CSV structure ────────────────────────────────────────
    c1 = 0
    if result.get('csv_exists'):
        c1 += 4
        if result.get('csv_is_new'):
            c1 += 4
        if result.get('has_zone_id'):
            c1 += 2
        if result.get('has_total_jobs'):
            c1 += 2
        if result.get('has_total_households'):
            c1 += 2
        if result.get('has_equity_gap_score'):
            c1 += 3
        # Coverage: at least 30 zones
        min_zones = metadata.get('min_zones', 30)
        unique_zones = result.get('unique_zones', 0)
        if unique_zones >= min_zones:
            c1 += 3
        elif unique_zones >= 10:
            c1 += 1
    score += c1
    fb.append(f"C1 csv-structure: {c1}/20 (zones={result.get('unique_zones', 0)})")

    # ── Criterion 2: Equity gap score validity ────────────────────────────
    c2 = 0
    if result.get('has_equity_gap_score') and result.get('csv_exists'):
        eq_min = result.get('equity_score_min')
        eq_max = result.get('equity_score_max')
        eq_std = result.get('equity_score_std')

        if eq_min is not None:
            c2 += 5  # scores were parseable as floats
        if result.get('all_scores_in_0_1'):
            c2 += 10
        if result.get('scores_vary'):
            c2 += 5  # not all identical
    score += c2
    fb.append(f"C2 equity-score-validity: {c2}/20 "
              f"(min={result.get('equity_score_min')}, "
              f"max={result.get('equity_score_max')}, "
              f"std={result.get('equity_score_std')})")

    # ── Criterion 3: Supplementary column plausibility ───────────────────
    c3 = 0
    if result.get('has_low_income_share'):
        c3 += 4
        if result.get('low_income_share_in_range'):
            c3 += 8
    if result.get('has_jobs_per_household'):
        c3 += 4
        if result.get('jobs_per_hh_nonnegative'):
            c3 += 4
    score += c3
    fb.append(f"C3 supplementary-cols: {c3}/20")

    # ── Criterion 4: Chart ────────────────────────────────────────────────
    c4 = 0
    if result.get('chart_exists'):
        c4 += 8
        if result.get('chart_is_new'):
            c4 += 10
        if result.get('chart_size_kb', 0) > 5:
            c4 += 7
    score += c4
    fb.append(f"C4 chart: {c4}/25 (size={result.get('chart_size_kb', 0):.1f}KB)")

    # ── Criterion 5: Notebook executed ───────────────────────────────────
    c5 = 0
    exec_cells = result.get('notebook_executed_cells', 0)
    if exec_cells >= 5:
        c5 = 15
    elif exec_cells >= 3:
        c5 = 10
    elif exec_cells >= 1:
        c5 = 5
    score += c5
    fb.append(f"C5 notebook: {c5}/15 (executed={exec_cells})")

    score = min(score, 100)
    passed = score >= metadata.get('pass_threshold', 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }
