#!/usr/bin/env python3
"""Verifier for displacement_risk_analysis task.

Scoring (100 points total):
  Gate:       wrong-target / do-nothing check (returns 0 immediately if triggered)
  Criterion 1 (20 pts): CSV file exists, is new (post-task), and has >= 50 zone rows
  Criterion 2 (20 pts): All five required columns present (zone_id, dri_score,
                         vulnerability_score, precarity_score, pressure_score)
  Criterion 3 (20 pts): DRI scores are numeric, in [0,1], with std > 0 (meaningful variation)
  Criterion 4 (15 pts): Supplementary columns present (low_income_households,
                         mean_price_per_sqft) and numeric
  Criterion 5 (15 pts): Chart PNG exists, is new, and > 10 KB
  Criterion 6 (10 pts): Notebook has at least 3 executed code cells

Pass threshold: 60
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_displacement_risk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    result_path = "/tmp/displacement_risk_result.json"

    # ── Read exported result JSON ─────────────────────────────────────────
    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env(result_path, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

    # ── Do-nothing gate ───────────────────────────────────────────────────
    if not result.get('csv_exists') and not result.get('chart_exists'):
        return {"passed": False, "score": 0, "feedback": "No output files produced (do-nothing)"}

    score = 0
    fb = []

    # ── Criterion 1: CSV exists, is new, has >= 50 zone rows ─────────────
    c1 = 0
    min_zones = metadata.get('min_zones', 50)
    if result.get('csv_exists'):
        c1 += 5
        if result.get('csv_is_new'):
            c1 += 8
        row_count = result.get('csv_row_count', 0)
        if row_count >= min_zones:
            c1 += 7
        elif row_count >= 10:
            c1 += 3
    score += c1
    fb.append(f"C1 csv-existence/freshness/coverage: {c1}/20 (rows={result.get('csv_row_count',0)})")

    # ── Criterion 2: All five required columns present ────────────────────
    c2 = 0
    required = [
        ('has_zone_id', 'zone_id'),
        ('has_dri_score', 'dri_score'),
        ('has_vulnerability_score', 'vulnerability_score'),
        ('has_precarity_score', 'precarity_score'),
        ('has_pressure_score', 'pressure_score'),
    ]
    pts_per = 4
    for key, col_name in required:
        if result.get(key):
            c2 += pts_per
    score += c2
    fb.append(f"C2 required-columns: {c2}/20")

    # ── Criterion 3: DRI scores numeric, in [0,1], meaningful variation ──
    c3 = 0
    if result.get('has_dri_score') and result.get('csv_row_count', 0) > 0:
        dri_min = result.get('dri_score_min')
        dri_max = result.get('dri_score_max')
        dri_std = result.get('dri_score_std')
        if dri_min is not None and dri_max is not None:
            c3 += 5  # numeric values present
            if result.get('all_dri_in_0_1'):
                c3 += 8  # all values in [0,1]
            if dri_std is not None and dri_std > 0.01:
                c3 += 7  # meaningful variation (not all same)
    score += c3
    fb.append(f"C3 dri-validity: {c3}/20 (std={result.get('dri_score_std')})")

    # ── Criterion 4: Supplementary columns present with numeric values ────
    c4 = 0
    if result.get('has_low_income_households'):
        c4 += 7
    if result.get('has_mean_price_per_sqft'):
        c4 += 8
    score += c4
    fb.append(f"C4 supplementary-columns: {c4}/15")

    # ── Criterion 5: Chart PNG exists, is new, > 10 KB ───────────────────
    c5 = 0
    if result.get('chart_exists'):
        c5 += 5
        if result.get('chart_is_new'):
            c5 += 5
        if result.get('chart_size_kb', 0) > 10:
            c5 += 5
    score += c5
    fb.append(f"C5 chart: {c5}/15 (size={result.get('chart_size_kb',0):.1f}KB)")

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
    fb.append(f"C6 notebook-execution: {c6}/10 (executed_cells={exec_cells})")

    # ── VLM check (bonus, up to 5 pts absorbed within ceiling) ───────────
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj and score >= 40:
        try:
            from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
            final = get_final_screenshot(traj)
            frames = sample_trajectory_frames(traj, num_samples=3) if traj else []
            images = [f for f in ([final] + frames) if f is not None][:4]
            if images:
                vlm_result = query_vlm(
                    images=images,
                    prompt=(
                        "These screenshots show a Jupyter Lab session computing a Displacement Risk Index for SF zones.\n"
                        "Answer as JSON:\n"
                        "1. 'bar_chart_visible': Is a horizontal bar chart of risk scores visible?\n"
                        "2. 'multiple_zones_visible': Are results for more than 10 zones visible?\n"
                        "3. 'code_executed': Are there code cells with visible output?\n"
                        "Return: {\"bar_chart_visible\": bool, \"multiple_zones_visible\": bool, \"code_executed\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict):
                    parsed = vlm_result.get('parsed', {})
                    vlm_bonus = 0
                    if parsed.get('bar_chart_visible'):
                        vlm_bonus += 2
                    if parsed.get('multiple_zones_visible'):
                        vlm_bonus += 2
                    if parsed.get('code_executed'):
                        vlm_bonus += 1
                    score += vlm_bonus
                    fb.append(f"VLM-bonus: {vlm_bonus}/5")
        except Exception:
            pass

    score = min(score, 100)
    passed = score >= metadata.get('pass_threshold', 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }
