#!/usr/bin/env python3
"""
Verifier for crop_pest_scouting task.

IPM Economic Thresholds (University of Iowa Extension):
  soybean_aphid_per_plant > 250
  corn_rootworm_beetles_per_trap > 5
  corn_borer_egg_masses_per_100 > 10
  bean_leaf_beetle_per_sweep > 8
  defoliation_pct > 20

A zone should be 'TREAT' if ANY count exceeds its threshold.

Scoring (total 100 pts):
  Correct TREAT recommendation: 6 pts each (10 zones × 6 = 60 pts)
  Non-empty action_notes for TREAT zone: 2 pts each (10 × 2 = 20 pts)
  recheck_date present and roughly 7 days after scout_date: 1 pt each (10 × 1 = 10 pts)
  False positive penalty (MONITOR zone incorrectly set TREAT): −4 pts each
  Precision bonus (+10 pts) if false positives = 0 AND ≥8 correct TREAT

Pass threshold: 60 pts
"""

import sqlite3
import tempfile
import os
from datetime import date, timedelta

APHID_THRESHOLD = 250.0
ROOTWORM_THRESHOLD = 5.0
BORER_THRESHOLD = 10.0
BEETLE_THRESHOLD = 8.0
DEFOLIATION_THRESHOLD = 20.0

POINTS_TREAT = 6
POINTS_NOTES = 2
POINTS_RECHECK = 1
PENALTY_FP = 4
BONUS = 10
PASS_THRESHOLD = 60


def _exceeds_threshold(row):
    """Return True if any pest count exceeds IPM economic threshold."""
    aphid = row['soybean_aphid_per_plant']
    rootworm = row['corn_rootworm_beetles_per_trap']
    borer = row['corn_borer_egg_masses_per_100']
    beetle = row['bean_leaf_beetle_per_sweep']
    defoliation = row['defoliation_pct']

    return (
        (aphid is not None and aphid > APHID_THRESHOLD) or
        (rootworm is not None and rootworm > ROOTWORM_THRESHOLD) or
        (borer is not None and borer > BORER_THRESHOLD) or
        (beetle is not None and beetle > BEETLE_THRESHOLD) or
        (defoliation is not None and defoliation > DEFOLIATION_THRESHOLD)
    )


def _recheck_date_valid(scout_date_str, recheck_str):
    """Return True if recheck_date is within 3–14 days of scout_date."""
    if not recheck_str or not scout_date_str:
        return False
    try:
        scout = date.fromisoformat(scout_date_str[:10])
        recheck = date.fromisoformat(recheck_str[:10])
        delta = (recheck - scout).days
        return 3 <= delta <= 14
    except (ValueError, AttributeError):
        return False


def check_crop_pest_scouting(traj, env_info, task_info):
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/crop_pest_scouting_result.gpkg'
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
            "SELECT zone_id, crop_type, scout_date, "
            "soybean_aphid_per_plant, corn_rootworm_beetles_per_trap, "
            "corn_borer_egg_masses_per_100, bean_leaf_beetle_per_sweep, "
            "defoliation_pct, treatment_recommendation, action_notes, recheck_date "
            "FROM scout_zones"
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
                'feedback': 'scout_zones table is empty.'}

    score = 0
    details = []
    n_correct = 0
    n_fp = 0

    for row in rows:
        should_treat = _exceeds_threshold(row)
        is_treat = (row['treatment_recommendation'] or '').strip().upper() == 'TREAT'
        has_notes = bool((row['action_notes'] or '').strip())
        recheck_ok = _recheck_date_valid(row['scout_date'], row['recheck_date'])
        zone = row['zone_id'] or 'unknown'

        if should_treat:
            if is_treat:
                score += POINTS_TREAT
                n_correct += 1
                details.append(f'PASS  {zone}: correctly set TREAT (+{POINTS_TREAT}pts)')
                if has_notes:
                    score += POINTS_NOTES
                    details.append(f'PASS  {zone}: action_notes present (+{POINTS_NOTES}pts)')
                else:
                    details.append(f'FAIL  {zone}: TREAT but action_notes is empty')
                if recheck_ok:
                    score += POINTS_RECHECK
                    details.append(f'PASS  {zone}: recheck_date valid (+{POINTS_RECHECK}pt)')
                else:
                    details.append(f'FAIL  {zone}: recheck_date missing or out of range')
            else:
                details.append(f'FAIL  {zone}: exceeds IPM threshold but still MONITOR')
        else:
            if is_treat:
                score -= PENALTY_FP
                n_fp += 1
                details.append(
                    f'FP    {zone}: incorrectly set TREAT (all counts below threshold) '
                    f'(−{PENALTY_FP}pts)'
                )

    if n_fp == 0 and n_correct >= 8:
        score += BONUS
        details.append(f'BONUS: ≥8 correct TREAT, 0 false positives (+{BONUS}pts)')

    score = max(0, min(100, score))
    passed = score >= PASS_THRESHOLD

    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        f'Zones correctly set TREAT: {n_correct}\n'
        f'False positives: {n_fp}\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
