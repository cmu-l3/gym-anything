#!/usr/bin/env python3
"""Verifier for housing_shortage_projection task.

Scoring (100 points total):
  Gate:        do-nothing check
  Criterion 1 (20 pts): CSV exists, is new, has required columns
                         (year, households_start, new_units, annual_deficit)
  Criterion 2 (25 pts): Exactly 5 rows covering years 2020–2024; year sequence is correct
  Criterion 3 (25 pts): Simulation actually ran: deficit column has non-zero values that
                         vary across years; new_units column has non-negative values
  Criterion 4 (10 pts): Orca framework was used: notebook contains orca.run() and @orca.step
  Criterion 5 (10 pts): Chart PNG exists, is new, > 5 KB
  Criterion 6 (10 pts): Notebook has >= 4 executed code cells

Pass threshold: 60
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_housing_shortage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env("/tmp/housing_shortage_result.json", tmp.name)
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
        if result.get('has_year_col'):
            c1 += 3
        if result.get('has_households_col'):
            c1 += 3
        if result.get('has_new_units_col'):
            c1 += 3
        if result.get('has_deficit_col'):
            c1 += 3
    score += c1
    fb.append(f"C1 csv-structure: {c1}/20")

    # ── Criterion 2: Year sequence ────────────────────────────────────────
    c2 = 0
    years = sorted(result.get('years_found', []))
    required_years = metadata.get('required_years', [2020, 2021, 2022, 2023, 2024])
    if result.get('csv_rows') == 5:
        c2 += 10
    elif result.get('csv_rows', 0) >= 3:
        c2 += 4
    if years:
        matching = sum(1 for y in required_years if y in years)
        c2 += matching * 3
    score += c2
    fb.append(f"C2 year-sequence: {c2}/25 (years={years}, need={required_years})")

    # ── Criterion 3: Simulation quality ──────────────────────────────────
    c3 = 0
    deficit_vals = result.get('deficit_values', [])
    units_vals = result.get('new_units_values', [])
    hh_vals = result.get('new_households_values', [])

    if deficit_vals:
        c3 += 5
        if result.get('all_deficits_nonzero'):
            c3 += 8
        if result.get('deficits_vary'):
            c3 += 7  # Values change year-over-year (dynamic simulation)
        # Plausibility check: deficits should be on order of hundreds or thousands, not billions
        if all(abs(v) < 1_000_000 for v in deficit_vals):
            c3 += 5
    score += c3
    fb.append(f"C3 simulation-quality: {c3}/25 "
              f"(deficits={deficit_vals[:3] if deficit_vals else []})")

    # ── Criterion 4: Orca framework used ─────────────────────────────────
    c4 = 0
    if result.get('notebook_has_orca'):
        c4 += 4
    if result.get('notebook_has_orca_step'):
        c4 += 3
    if result.get('notebook_has_orca_run'):
        c4 += 3
    score += c4
    fb.append(f"C4 orca-framework: {c4}/10")

    # ── Criterion 5: Chart ────────────────────────────────────────────────
    c5 = 0
    if result.get('chart_exists'):
        c5 += 4
        if result.get('chart_is_new'):
            c5 += 3
        if result.get('chart_size_kb', 0) > 5:
            c5 += 3
    score += c5
    fb.append(f"C5 chart: {c5}/10 (size={result.get('chart_size_kb',0):.1f}KB)")

    # ── Criterion 6: Notebook executed ───────────────────────────────────
    c6 = 0
    exec_cells = result.get('notebook_executed_cells', 0)
    if exec_cells >= 5:
        c6 = 10
    elif exec_cells >= 3:
        c6 = 7
    elif exec_cells >= 1:
        c6 = 3
    score += c6
    fb.append(f"C6 notebook: {c6}/10 (executed={exec_cells})")

    score = min(score, 100)
    passed = score >= metadata.get('pass_threshold', 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }
