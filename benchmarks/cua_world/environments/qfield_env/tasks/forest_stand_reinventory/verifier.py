#!/usr/bin/env python3
"""
Verifier for forest_stand_reinventory task.

Reference date: 2024-07-01
Overdue threshold: last_inventory_date year <= 2019 (5+ years before 2024)

Scoring (total 100 pts):
  For each overdue stand correctly set to OVERDUE:        4 pts each (~14 stands × 4 = 56 pts)
  Non-empty field_notes for OVERDUE stand:                1 pt each (~14 × 1 = 14 pts)
  Correct priority_rank (1 for >7yr, 2 for 5-7yr):       1 pt each (~14 × 1 = 14 pts)
  At least 1 tree_measurements record for OVERDUE stand:  1 pt each (~14 × 1 = 14 pts)
    (capped: tree_measurements bonus caps at 14 pts total)
  False positive penalty (CURRENT stand → OVERDUE):      −4 pts each

Pass threshold: 60 pts
"""

import sqlite3
import tempfile
import os

REFERENCE_YEAR = 2024
OVERDUE_CUTOFF_YEAR = 2019  # <= 2019 means 5+ years overdue
VERY_OVERDUE_CUTOFF_YEAR = 2016  # <= 2016 means 8+ years overdue → priority_rank 1

POINTS_STATUS = 4
POINTS_NOTES = 1
POINTS_PRIORITY = 1
POINTS_TREE_MEAS = 1
PENALTY_FP = 4
PASS_THRESHOLD = 60


def _is_overdue(inv_date_str):
    """Return True if last_inventory_date year <= OVERDUE_CUTOFF_YEAR."""
    if not inv_date_str:
        return False
    try:
        year = int(str(inv_date_str)[:4])
        return year <= OVERDUE_CUTOFF_YEAR
    except (ValueError, TypeError):
        return False


def _expected_priority(inv_date_str):
    """Return expected priority_rank: 1 for very overdue (>7yr), 2 for 5-7yr."""
    try:
        year = int(str(inv_date_str)[:4])
        years_overdue = REFERENCE_YEAR - year
        if years_overdue > 7:
            return 1
        else:
            return 2
    except (ValueError, TypeError):
        return 2


def check_forest_stand_reinventory(traj, env_info, task_info):
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/forest_stand_reinventory_result.gpkg'
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

        stands = conn.execute(
            "SELECT fid, stand_id, last_inventory_date, reinventory_status, "
            "field_notes, priority_rank FROM forest_stands"
        ).fetchall()

        # Check tree_measurements table
        tree_meas_by_stand = {}
        try:
            tree_rows = conn.execute(
                "SELECT stand_id, COUNT(*) as cnt FROM tree_measurements GROUP BY stand_id"
            ).fetchall()
            for tr in tree_rows:
                tree_meas_by_stand[tr['stand_id']] = tr['cnt']
        except Exception:
            tree_meas_by_stand = {}

        conn.close()
    except Exception as e:
        return {'passed': False, 'score': 0,
                'feedback': f'Failed to query GeoPackage: {e}'}
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

    if not stands:
        return {'passed': False, 'score': 0,
                'feedback': 'forest_stands table is empty.'}

    score = 0
    details = []
    n_correct = 0
    n_fp = 0
    tree_bonus_total = 0
    max_tree_bonus = 14

    for row in stands:
        should_be_overdue = _is_overdue(row['last_inventory_date'])
        is_overdue = (row['reinventory_status'] or '').strip().upper() == 'OVERDUE'
        has_notes = bool((row['field_notes'] or '').strip())
        stand_id = row['stand_id'] or 'unknown'
        fid = row['fid']

        # Check tree measurements for this stand
        has_tree_meas = tree_meas_by_stand.get(stand_id, 0) > 0

        if should_be_overdue:
            if is_overdue:
                score += POINTS_STATUS
                n_correct += 1
                details.append(
                    f'PASS  {stand_id} [{row["last_inventory_date"]}]: '
                    f'correctly set OVERDUE (+{POINTS_STATUS}pts)'
                )

                if has_notes:
                    score += POINTS_NOTES
                    details.append(f'PASS  {stand_id}: field_notes present (+{POINTS_NOTES}pt)')
                else:
                    details.append(f'FAIL  {stand_id}: OVERDUE but field_notes empty')

                exp_priority = _expected_priority(row['last_inventory_date'])
                actual_priority = row['priority_rank']
                if actual_priority == exp_priority:
                    score += POINTS_PRIORITY
                    details.append(
                        f'PASS  {stand_id}: priority_rank={actual_priority} correct '
                        f'(+{POINTS_PRIORITY}pt)'
                    )
                else:
                    details.append(
                        f'FAIL  {stand_id}: priority_rank={actual_priority}, '
                        f'expected {exp_priority}'
                    )

                if has_tree_meas and tree_bonus_total < max_tree_bonus:
                    score += POINTS_TREE_MEAS
                    tree_bonus_total += POINTS_TREE_MEAS
                    details.append(
                        f'PASS  {stand_id}: tree_measurements record present '
                        f'(+{POINTS_TREE_MEAS}pt)'
                    )
                elif not has_tree_meas:
                    details.append(
                        f'FAIL  {stand_id}: no tree_measurements records added for this stand'
                    )
            else:
                details.append(
                    f'FAIL  {stand_id} [{row["last_inventory_date"]}]: '
                    f'overdue stand still marked CURRENT'
                )
        else:
            if is_overdue:
                score -= PENALTY_FP
                n_fp += 1
                details.append(
                    f'FP    {stand_id} [{row["last_inventory_date"]}]: '
                    f'incorrectly marked OVERDUE (inventoried within 5 years) '
                    f'(−{PENALTY_FP}pts)'
                )

    score = max(0, min(100, score))
    passed = score >= PASS_THRESHOLD

    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        f'Stands correctly marked OVERDUE: {n_correct}\n'
        f'False positives (incorrectly marked OVERDUE): {n_fp}\n'
        f'Tree measurement bonus earned: {tree_bonus_total}/{max_tree_bonus} pts\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
