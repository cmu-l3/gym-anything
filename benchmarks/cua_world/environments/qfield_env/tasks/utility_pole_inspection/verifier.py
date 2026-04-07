#!/usr/bin/env python3
"""
Verifier for utility_pole_inspection task.

Replacement criteria (ALL three must be true simultaneously):
  1. material = 'Wood'
  2. install_year < 2010
  3. condition_rating IN ('Fair', 'Poor', 'Critical')

Scoring (total 100 pts):
  Correct SCHEDULE for poles meeting all 3 criteria: 5 pts each (expect ~12-13 poles)
  Non-empty work_order_notes for SCHEDULE poles: 2 pts each
  False positive penalty (OK pole incorrectly flagged SCHEDULE): −4 pts each
  Precision bonus (+15 pts) if false positives = 0 AND ≥10 correct flags

Pass threshold: 60 pts
"""

import sqlite3
import tempfile
import os

REPLACEMENT_CONDITIONS = ('Fair', 'Poor', 'Critical')
REPLACEMENT_MATERIAL = 'Wood'
REPLACEMENT_YEAR_CUTOFF = 2010

POINTS_CORRECT_FLAG = 5
POINTS_NOTES = 2
PENALTY_FP = 4
BONUS_PRECISION = 15
PASS_THRESHOLD = 60


def _meets_replacement_criteria(row):
    material = (row['material'] or '').strip()
    try:
        year = int(row['install_year'] or 9999)
    except (ValueError, TypeError):
        year = 9999
    condition = (row['condition_rating'] or '').strip()

    return (
        material == REPLACEMENT_MATERIAL
        and year < REPLACEMENT_YEAR_CUTOFF
        and condition in REPLACEMENT_CONDITIONS
    )


def check_utility_pole_inspection(traj, env_info, task_info):
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/utility_pole_inspection_result.gpkg'
    )

    tmp = tempfile.mktemp(suffix='.gpkg')
    try:
        env_info['copy_from_env'](result_path, tmp)
    except Exception as e:
        return {'passed': False, 'score': 0,
                'feedback': f'Could not retrieve GeoPackage: {e}'}

    if not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        return {'passed': False, 'score': 0,
                'feedback': 'GeoPackage file is empty or missing.'}

    try:
        conn = sqlite3.connect(tmp)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT pole_id, material, install_year, condition_rating, "
            "replacement_flag, work_order_notes FROM pole_inventory"
        ).fetchall()
        conn.close()
    except Exception as e:
        return {'passed': False, 'score': 0,
                'feedback': f'Failed to query GeoPackage: {e}'}
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

    if not rows:
        return {'passed': False, 'score': 0,
                'feedback': 'pole_inventory table is empty.'}

    score = 0
    details = []
    n_correct = 0
    n_fp = 0

    for row in rows:
        should_flag = _meets_replacement_criteria(row)
        is_flagged = (row['replacement_flag'] or '').strip().upper() == 'SCHEDULE'
        has_notes = bool((row['work_order_notes'] or '').strip())
        pole = row['pole_id'] or 'unknown'
        mat = row['material']
        yr = row['install_year']
        cond = row['condition_rating']

        if should_flag:
            if is_flagged:
                score += POINTS_CORRECT_FLAG
                n_correct += 1
                details.append(
                    f'PASS  {pole} [{mat}, {yr}, {cond}]: correctly SCHEDULE (+{POINTS_CORRECT_FLAG}pts)'
                )
                if has_notes:
                    score += POINTS_NOTES
                    details.append(f'PASS  {pole}: work_order_notes present (+{POINTS_NOTES}pts)')
                else:
                    details.append(f'FAIL  {pole}: SCHEDULE but no work_order_notes')
            else:
                details.append(
                    f'FAIL  {pole} [{mat}, {yr}, {cond}]: meets all 3 criteria but not flagged SCHEDULE'
                )
        else:
            if is_flagged:
                score -= PENALTY_FP
                n_fp += 1
                details.append(
                    f'FP    {pole} [{mat}, {yr}, {cond}]: incorrectly flagged SCHEDULE '
                    f'(does NOT meet all 3 criteria) (−{PENALTY_FP}pts)'
                )

    # Precision bonus
    if n_fp == 0 and n_correct >= 10:
        score += BONUS_PRECISION
        details.append(
            f'BONUS: all criteria-meeting poles found, 0 false positives (+{BONUS_PRECISION}pts)'
        )

    score = max(0, min(100, score))
    passed = score >= PASS_THRESHOLD

    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        f'Correctly flagged SCHEDULE: {n_correct}\n'
        f'False positives (incorrectly flagged): {n_fp}\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
