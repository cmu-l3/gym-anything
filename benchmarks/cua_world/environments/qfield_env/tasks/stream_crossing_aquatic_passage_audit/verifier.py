#!/usr/bin/env python3
"""
Verifier for stream_crossing_aquatic_passage_audit task.

Checks that the agent correctly identified 12 stream crossings marked 'PASSING'
that actually fail USFS Aquatic Organism Passage (AOP) criteria:

USFS AOP Design Guide 2021 / ODFW passage criteria:
  outlet_drop_cm <= 12.0          (> 12 cm outlet drop = barrier for juvenile salmonids)
  outlet_width / bankfull_width >= 0.8  (< 0.8 = hydraulic constriction)
  slope_pct <= 10.0               (> 10% channel slope = passage barrier)
  structure_type NOT IN ('perched_culvert', 'box_culvert_undersized')
  substrate_type NOT IN ('concrete_smooth', 'metal_smooth')

Contaminated crossings (seeded as PASSING but failing AOP criterion):
  WNF-XR-001: outlet_drop=18.5 cm (> 12 cm)
  WNF-XR-002: outlet_w/bankfull=1.4/2.2=0.64 (< 0.8)
  WNF-XR-003: slope=13.5% (> 10%)
  WNF-XR-004: structure=perched_culvert (barrier structure)
  WNF-XR-005: substrate=concrete_smooth (barrier substrate)
  WNF-XR-006: outlet_drop=20.0 cm (> 12 cm)
  WNF-XR-007: outlet_w/bankfull=1.0/2.8=0.36 (< 0.8)
  WNF-XR-008: slope=15.0% (> 10%)
  WNF-XR-009: structure=box_culvert_undersized (barrier structure)
  WNF-XR-010: substrate=metal_smooth (barrier substrate)
  WNF-XR-011: outlet_drop=22.0 cm (> 12 cm)
  WNF-XR-012: outlet_w/bankfull=0.9/2.5=0.36 (< 0.8)

Scoring (100 pts total):
  - Each contaminated crossing correctly changed to FAILING: 6 pts × 12 = 72 pts
  - Each corrected crossing with non-empty passage_barrier_note: 1 pt × 12 = 12 pts
  - False positives (genuinely PASSING crossings wrongly changed): -5 pts each
  - Bonus: all 12 corrected with zero false positives: +16 pts
Pass threshold: 60 pts
"""

import sqlite3
import tempfile
import os

CONTAMINATED_CROSSING_IDS = [
    'WNF-XR-001', 'WNF-XR-002', 'WNF-XR-003', 'WNF-XR-004',
    'WNF-XR-005', 'WNF-XR-006', 'WNF-XR-007', 'WNF-XR-008',
    'WNF-XR-009', 'WNF-XR-010', 'WNF-XR-011', 'WNF-XR-012',
]

# USFS AOP criteria thresholds
AOP_CRITERIA = {
    'max_outlet_drop_cm': 12.0,
    'min_width_ratio': 0.8,
    'max_slope_pct': 10.0,
    'barrier_structure_types': ['perched_culvert', 'box_culvert_undersized'],
    'barrier_substrates': ['concrete_smooth', 'metal_smooth'],
}

POINTS_PER_STATUS = 6
POINTS_PER_NOTE = 1
FALSE_POSITIVE_PENALTY = 5
BONUS_ALL_CORRECT = 16
PASS_THRESHOLD = 60


def _crossing_fails_aop(row):
    """Return True if this crossing fails at least one AOP criterion."""
    drop = row['outlet_drop_cm']
    outlet_w = row['outlet_width_m']
    bankfull_w = row['bankfull_width_m']
    slope = row['slope_pct']
    struct = (row['structure_type'] or '').lower()
    substrate = (row['substrate_type'] or '').lower()

    if drop is not None and drop > AOP_CRITERIA['max_outlet_drop_cm']:
        return True
    if outlet_w is not None and bankfull_w and bankfull_w > 0:
        if outlet_w / bankfull_w < AOP_CRITERIA['min_width_ratio']:
            return True
    if slope is not None and slope > AOP_CRITERIA['max_slope_pct']:
        return True
    if struct in AOP_CRITERIA['barrier_structure_types']:
        return True
    if substrate in AOP_CRITERIA['barrier_substrates']:
        return True
    return False


def check_stream_crossing_aquatic_passage_audit(traj, env_info, task_info):
    """
    Pull the modified GeoPackage from the Android device and verify that
    non-compliant stream crossings have been updated from PASSING to FAILING.
    """
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/stream_crossing_aquatic_passage_audit_result.gpkg'
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
            "SELECT crossing_id, aop_status, passage_barrier_note, "
            "outlet_drop_cm, outlet_width_m, bankfull_width_m, "
            "slope_pct, structure_type, substrate_type "
            "FROM stream_crossings"
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
            'feedback': 'No crossings found in stream_crossings table.'
        }

    crossing_data = {row['crossing_id']: row for row in rows}

    score = 0
    details = []
    false_positives = 0
    contaminated_caught = 0

    for cid in CONTAMINATED_CROSSING_IDS:
        if cid not in crossing_data:
            details.append(f'MISS  {cid}: not found in layer')
            continue

        row = crossing_data[cid]
        current_status = (row['aop_status'] or '').strip().upper()
        current_note = (row['passage_barrier_note'] or '').strip()

        if current_status == 'FAILING':
            score += POINTS_PER_STATUS
            contaminated_caught += 1
            details.append(f'PASS  {cid}: correctly changed to FAILING (+{POINTS_PER_STATUS}pts)')
        elif current_status == 'PASSING':
            # Provide diagnostic info
            width_ratio = None
            if row['outlet_width_m'] and row['bankfull_width_m'] and row['bankfull_width_m'] > 0:
                width_ratio = round(row['outlet_width_m'] / row['bankfull_width_m'], 2)
            details.append(
                f'FAIL  {cid}: still PASSING — check: '
                f'outlet_drop={row["outlet_drop_cm"]}cm, '
                f'width_ratio={width_ratio}, '
                f'slope={row["slope_pct"]}%, '
                f'structure={row["structure_type"]}, '
                f'substrate={row["substrate_type"]}'
            )
        else:
            details.append(f'PARTIAL  {cid}: status changed to {current_status} (expected FAILING)')

        if current_note:
            score += POINTS_PER_NOTE
            details.append(f'PASS  {cid}: passage_barrier_note present (+{POINTS_PER_NOTE}pts): "{current_note[:60]}"')
        else:
            details.append(f'FAIL  {cid}: passage_barrier_note is empty — describe the passage barrier')

    # Check for false positives among background crossings
    for cid, row in crossing_data.items():
        if cid in CONTAMINATED_CROSSING_IDS:
            continue
        current_status = (row['aop_status'] or '').strip().upper()
        if current_status == 'FAILING':
            if not _crossing_fails_aop(row):
                false_positives += 1
                score -= FALSE_POSITIVE_PENALTY
                details.append(
                    f'FALSE_POSITIVE  {cid}: changed to FAILING but crossing '
                    f'meets all AOP criteria (-{FALSE_POSITIVE_PENALTY}pts)'
                )

    if contaminated_caught == len(CONTAMINATED_CROSSING_IDS) and false_positives == 0:
        score += BONUS_ALL_CORRECT
        details.append(
            f'BONUS: All {len(CONTAMINATED_CROSSING_IDS)} non-compliant crossings '
            f'corrected with zero false positives (+{BONUS_ALL_CORRECT}pts)'
        )

    score = max(0, score)
    passed = score >= PASS_THRESHOLD
    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        f'Non-compliant crossings corrected: {contaminated_caught}/{len(CONTAMINATED_CROSSING_IDS)}\n'
        f'False positives: {false_positives}\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
