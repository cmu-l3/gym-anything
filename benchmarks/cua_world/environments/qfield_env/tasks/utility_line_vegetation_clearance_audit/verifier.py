#!/usr/bin/env python3
"""
Verifier for utility_line_vegetation_clearance_audit task.

Checks that the agent correctly identified 10 trees marked 'COMPLIANT' that
actually fail NERC FAC-003-4 and ANSI A300 Part 7 vegetation clearance standards.

Clearance criteria:
  Zone 1 encroachment: distance_to_conductor_m < 3.05  → TRIM_REQUIRED
  Grow-in violation:   height_m > (conductor_height_m - 3.0)  → TRIM_REQUIRED
  Fall-in risk:        lean_toward_line=1 AND height_m > distance_to_conductor_m * 1.2

Contaminated trees (seeded as COMPLIANT but failing criterion):
  VEG-001: zone1_encroachment (dist=1.5m < 3.05m)
  VEG-002: grow_in (height=14.5m > conductor 12.0 - 3.0 = 9.0m)
  VEG-003: zone1_encroachment (dist=2.8m < 3.05m)
  VEG-004: fall_in_risk (lean=1, height=12.5m > 9.0*1.2=10.8m)
  VEG-005: zone1_encroachment (dist=2.1m < 3.05m)
  VEG-006: grow_in (height=15.0m > conductor 12.0 - 3.0 = 9.0m)
  VEG-007: fall_in_risk (lean=1, height=11.5m > 8.5*1.2=10.2m)
  VEG-008: zone1_encroachment (dist=2.5m < 3.05m)
  VEG-009: grow_in (height=14.2m > conductor 11.0 - 3.0 = 8.0m)
  VEG-010: fall_in_risk (lean=1, height=10.8m > 7.8*1.2=9.36m)

Scoring (100 pts total):
  - Each non-compliant tree correctly changed to TRIM_REQUIRED: 8 pts × 10 = 80 pts
  - Each corrected tree with non-empty trim_reason: 1 pt × 10 = 10 pts
  - False positives (genuinely compliant trees wrongly changed): -6 pts each
  - Bonus: all 10 corrected with zero false positives: +10 pts
Pass threshold: 60 pts
"""

import sqlite3
import tempfile
import os

CONTAMINATED_TREE_IDS = [
    'VEG-001', 'VEG-002', 'VEG-003', 'VEG-004', 'VEG-005',
    'VEG-006', 'VEG-007', 'VEG-008', 'VEG-009', 'VEG-010',
]

# NERC FAC-003-4 clearance thresholds
NERC_CRITERIA = {
    'zone1_max_distance_m': 3.05,   # Zone 1 boundary (10 ft)
    'min_vertical_clearance_m': 3.0, # minimum conductor-to-tree height gap
    'fall_in_safety_factor': 1.2,    # tree height > dist * 1.2 = fall-in risk
}

POINTS_PER_STATUS = 8
POINTS_PER_REASON = 1
FALSE_POSITIVE_PENALTY = 6
BONUS_ALL_CORRECT = 10
PASS_THRESHOLD = 60


def _tree_fails_clearance(row):
    """Return True if tree fails at least one NERC/ANSI clearance criterion."""
    dist = row['distance_to_conductor_m']
    height = row['height_m']
    cond_h = row['conductor_height_m']
    lean = row['lean_toward_line']

    # Zone 1 encroachment
    if dist is not None and dist < NERC_CRITERIA['zone1_max_distance_m']:
        return True
    # Grow-in violation
    if height is not None and cond_h is not None:
        if height > (cond_h - NERC_CRITERIA['min_vertical_clearance_m']):
            return True
    # Fall-in risk
    if lean and height is not None and dist is not None and dist > 0:
        if height > dist * NERC_CRITERIA['fall_in_safety_factor']:
            return True
    return False


def check_utility_line_vegetation_clearance_audit(traj, env_info, task_info):
    """
    Pull the modified GeoPackage from the Android device and verify that
    trees failing NERC/ANSI clearance have been updated to TRIM_REQUIRED.
    """
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/utility_line_vegetation_clearance_audit_result.gpkg'
    )

    tmp = tempfile.mktemp(suffix='.gpkg')
    try:
        env_info['copy_from_env'](result_path, tmp)
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Could not retrieve GeoPackage from device: {e}'
        }

    if not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        return {
            'passed': False,
            'score': 0,
            'feedback': 'GeoPackage file is empty or missing after copy.'
        }

    try:
        conn = sqlite3.connect(tmp)
        conn.row_factory = sqlite3.Row

        rows = conn.execute(
            "SELECT tree_id, clearance_status, trim_reason, "
            "height_m, conductor_height_m, distance_to_conductor_m, lean_toward_line "
            "FROM vegetation_survey"
        ).fetchall()
        conn.close()
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Failed to query GeoPackage: {e}'
        }
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

    if not rows:
        return {
            'passed': False,
            'score': 0,
            'feedback': 'No trees found in vegetation_survey table.'
        }

    tree_data = {row['tree_id']: row for row in rows}

    score = 0
    details = []
    false_positives = 0
    contaminated_caught = 0

    for tid in CONTAMINATED_TREE_IDS:
        if tid not in tree_data:
            details.append(f'MISS  {tid}: not found in layer')
            continue

        row = tree_data[tid]
        current_status = (row['clearance_status'] or '').strip().upper()
        current_reason = (row['trim_reason'] or '').strip()

        if current_status == 'TRIM_REQUIRED':
            score += POINTS_PER_STATUS
            contaminated_caught += 1
            details.append(f'PASS  {tid}: correctly changed to TRIM_REQUIRED (+{POINTS_PER_STATUS}pts)')
        elif current_status == 'COMPLIANT':
            dist = row['distance_to_conductor_m']
            h = row['height_m']
            cond_h = row['conductor_height_m']
            lean = row['lean_toward_line']
            details.append(
                f'FAIL  {tid}: still COMPLIANT — check: '
                f'dist={dist}m (zone1<3.05m?), '
                f'height={h}m vs conductor-3m={cond_h and round(cond_h-3.0,1)}m, '
                f'lean={lean}'
            )
        else:
            details.append(f'PARTIAL  {tid}: status={current_status} (expected TRIM_REQUIRED)')

        if current_reason:
            score += POINTS_PER_REASON
            details.append(f'PASS  {tid}: trim_reason present (+{POINTS_PER_REASON}pts): "{current_reason[:60]}"')
        else:
            details.append(f'FAIL  {tid}: trim_reason is empty — specify NERC criterion')

    # Check background trees for false positives
    for tid, row in tree_data.items():
        if tid in CONTAMINATED_TREE_IDS:
            continue
        current_status = (row['clearance_status'] or '').strip().upper()
        if current_status == 'TRIM_REQUIRED':
            if not _tree_fails_clearance(row):
                false_positives += 1
                score -= FALSE_POSITIVE_PENALTY
                details.append(
                    f'FALSE_POSITIVE  {tid}: changed to TRIM_REQUIRED but '
                    f'tree meets all NERC clearance criteria (-{FALSE_POSITIVE_PENALTY}pts)'
                )

    if contaminated_caught == len(CONTAMINATED_TREE_IDS) and false_positives == 0:
        score += BONUS_ALL_CORRECT
        details.append(
            f'BONUS: All {len(CONTAMINATED_TREE_IDS)} non-compliant trees '
            f'corrected with zero false positives (+{BONUS_ALL_CORRECT}pts)'
        )

    score = max(0, score)
    passed = score >= PASS_THRESHOLD
    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        f'Non-compliant trees corrected: {contaminated_caught}/{len(CONTAMINATED_TREE_IDS)}\n'
        f'False positives: {false_positives}\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
