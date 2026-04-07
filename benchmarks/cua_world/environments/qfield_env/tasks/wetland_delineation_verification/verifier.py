#!/usr/bin/env python3
"""
Verifier for wetland_delineation_verification task.

Cross-layer verification: the agent must read soil_borings data, aggregate
per wetland, classify wetland_boundaries, create verification_results
for rejected wetlands, and identify the primary_reference wetland.

Ground truth:
  WL-001: 2/2 positive borings -> CONFIRMED
  WL-002: 0/3 positive borings -> REJECTED
  WL-003: 2/2 positive borings -> CONFIRMED
  WL-004: 1/3 positive borings -> REJECTED
  WL-005: 2/2 positive borings -> CONFIRMED  (primary_reference: avg depth 8.5cm)
  WL-006: 0/2 positive borings -> REJECTED

Scoring (100 pts total):
  Wetland classification (field_verified correct):  8 pts x 6 = 48 pts
  Common attributes (verification_date correct):    1 pt  x 6 =  6 pts
  Common attributes (delineator correct):           1 pt  x 6 =  6 pts
  boundary_accuracy='FAILED' for rejected:          3 pts x 3 =  9 pts
  verification_results point with correct ID+finding: 3 pts x 3 = 9 pts
  verification_results notes listing negative borings: 2 pts x 3 = 6 pts
  primary_reference (WL-005 nwi_status updated):    8 pts      =  8 pts
  Bonus (all 6 correct + 0 false positives):        8 pts      =  8 pts
  Misclassification penalty:                       -5 pts each
  False positive verification_results:             -4 pts each
Pass threshold: 60 pts
"""

import sqlite3
import tempfile
import os

# Expected classification for each wetland
EXPECTED_CLASSIFICATION = {
    'WL-001': 'CONFIRMED',
    'WL-002': 'REJECTED',
    'WL-003': 'CONFIRMED',
    'WL-004': 'REJECTED',
    'WL-005': 'CONFIRMED',
    'WL-006': 'REJECTED',
}

REJECTED_IDS = ['WL-002', 'WL-004', 'WL-006']
CONFIRMED_IDS = ['WL-001', 'WL-003', 'WL-005']
PRIMARY_REFERENCE_ID = 'WL-005'

# Negative boring IDs per rejected wetland (for notes verification)
NEGATIVE_BORINGS = {
    'WL-002': ['SB-003', 'SB-004', 'SB-005'],
    'WL-004': ['SB-008', 'SB-010'],
    'WL-006': ['SB-013', 'SB-014'],
}

EXPECTED_DATE = '2024-09-15'
EXPECTED_DELINEATOR = 'Survey Team Alpha'

POINTS_CLASSIFICATION = 8
POINTS_DATE = 1
POINTS_DELINEATOR = 1
POINTS_BOUNDARY_ACCURACY = 3
POINTS_RESULT_POINT = 3
POINTS_RESULT_NOTES = 2
POINTS_PRIMARY_REF = 8
BONUS_ALL_CORRECT = 8
PENALTY_MISCLASSIFICATION = 5
PENALTY_FP_RESULT = 4
PASS_THRESHOLD = 60


def check_wetland_delineation_verification(traj, env_info, task_info):
    """
    Pull the modified GeoPackage and verify wetland classifications,
    attributes, verification_results points, and primary_reference.
    """
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/wetland_delineation_verification_result.gpkg',
    )

    tmp = tempfile.mktemp(suffix='.gpkg')
    try:
        env_info['copy_from_env'](result_path, tmp)
    except Exception as e:
        return {
            'passed': False, 'score': 0,
            'feedback': f'Could not retrieve GeoPackage from device: {e}',
        }

    if not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        return {
            'passed': False, 'score': 0,
            'feedback': 'GeoPackage file is empty or missing after copy.',
        }

    try:
        conn = sqlite3.connect(tmp)
        conn.row_factory = sqlite3.Row

        # Read wetland_boundaries
        wetlands = conn.execute(
            "SELECT wetland_id, field_verified, verification_date, "
            "delineator, boundary_accuracy, nwi_status "
            "FROM wetland_boundaries"
        ).fetchall()

        # Read verification_results
        try:
            results = conn.execute(
                "SELECT result_id, wetland_id, finding, notes "
                "FROM verification_results"
            ).fetchall()
        except Exception:
            results = []

        conn.close()
    except Exception as e:
        return {
            'passed': False, 'score': 0,
            'feedback': f'Failed to query GeoPackage: {e}',
        }
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

    if not wetlands:
        return {
            'passed': False, 'score': 0,
            'feedback': 'wetland_boundaries table is empty.',
        }

    wetland_data = {row['wetland_id']: row for row in wetlands}
    result_data = {row['wetland_id']: row for row in results}

    score = 0
    details = []
    n_correct = 0
    n_misclass = 0

    # --- Score wetland classifications and common attributes ---
    for wid, expected in EXPECTED_CLASSIFICATION.items():
        if wid not in wetland_data:
            details.append(f'MISS  {wid}: not found in wetland_boundaries')
            continue

        row = wetland_data[wid]
        actual = (row['field_verified'] or '').strip().upper()

        # Classification
        if actual == expected:
            score += POINTS_CLASSIFICATION
            n_correct += 1
            details.append(
                f'PASS  {wid}: field_verified={actual} correct '
                f'(+{POINTS_CLASSIFICATION}pts)'
            )
        elif actual and actual != expected:
            score -= PENALTY_MISCLASSIFICATION
            n_misclass += 1
            details.append(
                f'FAIL  {wid}: field_verified={actual}, '
                f'expected {expected} (-{PENALTY_MISCLASSIFICATION}pts)'
            )
        else:
            details.append(f'FAIL  {wid}: field_verified is NULL/empty')

        # verification_date
        actual_date = (row['verification_date'] or '').strip()
        if actual_date == EXPECTED_DATE:
            score += POINTS_DATE
            details.append(f'PASS  {wid}: verification_date correct (+{POINTS_DATE}pt)')
        elif actual_date:
            details.append(
                f'FAIL  {wid}: verification_date={actual_date}, '
                f'expected {EXPECTED_DATE}'
            )

        # delineator
        actual_delin = (row['delineator'] or '').strip()
        if actual_delin == EXPECTED_DELINEATOR:
            score += POINTS_DELINEATOR
            details.append(f'PASS  {wid}: delineator correct (+{POINTS_DELINEATOR}pt)')
        elif actual_delin:
            details.append(
                f'FAIL  {wid}: delineator="{actual_delin}", '
                f'expected "{EXPECTED_DELINEATOR}"'
            )

    # --- Score REJECTED-specific attributes ---
    for wid in REJECTED_IDS:
        if wid not in wetland_data:
            continue
        row = wetland_data[wid]

        # boundary_accuracy = FAILED
        actual_ba = (row['boundary_accuracy'] or '').strip().upper()
        if actual_ba == 'FAILED':
            score += POINTS_BOUNDARY_ACCURACY
            details.append(
                f'PASS  {wid}: boundary_accuracy=FAILED '
                f'(+{POINTS_BOUNDARY_ACCURACY}pts)'
            )
        else:
            details.append(
                f'FAIL  {wid}: boundary_accuracy="{actual_ba}", expected FAILED'
            )

        # verification_results point
        expected_result_id = f'{wid}_RESULT'
        if wid in result_data:
            rrow = result_data[wid]
            rid = (rrow['result_id'] or '').strip()
            rfinding = (rrow['finding'] or '').strip()

            if rid == expected_result_id and rfinding == 'INSUFFICIENT_HYDRIC_INDICATORS':
                score += POINTS_RESULT_POINT
                details.append(
                    f'PASS  {wid}: verification_results point correct '
                    f'(+{POINTS_RESULT_POINT}pts)'
                )
            elif rid or rfinding:
                details.append(
                    f'PARTIAL  {wid}: result_id="{rid}", finding="{rfinding}"'
                )

            # Check notes for negative boring IDs
            rnotes = (rrow['notes'] or '').strip()
            expected_negatives = NEGATIVE_BORINGS.get(wid, [])
            if rnotes and all(bid in rnotes for bid in expected_negatives):
                score += POINTS_RESULT_NOTES
                details.append(
                    f'PASS  {wid}: notes lists all negative borings '
                    f'(+{POINTS_RESULT_NOTES}pts)'
                )
            elif rnotes:
                # Partial credit if at least one boring is mentioned
                mentioned = sum(1 for bid in expected_negatives if bid in rnotes)
                if mentioned > 0:
                    details.append(
                        f'PARTIAL  {wid}: notes mentions {mentioned}/{len(expected_negatives)} '
                        f'negative borings'
                    )
                else:
                    details.append(f'FAIL  {wid}: notes present but no boring IDs found')
            else:
                details.append(f'FAIL  {wid}: notes is empty')
        else:
            details.append(
                f'FAIL  {wid}: no verification_results point found '
                f'(expected {expected_result_id})'
            )

    # --- Check for false positive verification_results ---
    fp_results = 0
    for rrow in results:
        rwid = (rrow['wetland_id'] or '').strip()
        if rwid and rwid not in REJECTED_IDS:
            fp_results += 1
            score -= PENALTY_FP_RESULT
            details.append(
                f'FP    verification_results for {rwid}: '
                f'not a rejected wetland (-{PENALTY_FP_RESULT}pts)'
            )

    # --- Score primary_reference ---
    if PRIMARY_REFERENCE_ID in wetland_data:
        actual_nwi = (wetland_data[PRIMARY_REFERENCE_ID]['nwi_status'] or '').strip()
        if actual_nwi == 'primary_reference':
            score += POINTS_PRIMARY_REF
            details.append(
                f'PASS  {PRIMARY_REFERENCE_ID}: nwi_status=primary_reference '
                f'(+{POINTS_PRIMARY_REF}pts)'
            )
        else:
            details.append(
                f'FAIL  {PRIMARY_REFERENCE_ID}: nwi_status="{actual_nwi}", '
                f'expected primary_reference'
            )

    # --- Bonus ---
    if n_correct == 6 and n_misclass == 0 and fp_results == 0:
        score += BONUS_ALL_CORRECT
        details.append(
            f'BONUS: All 6 classifications correct, 0 errors '
            f'(+{BONUS_ALL_CORRECT}pts)'
        )

    score = max(0, min(100, score))
    passed = score >= PASS_THRESHOLD

    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        f'Wetlands correctly classified: {n_correct}/6\n'
        f'Misclassifications: {n_misclass}\n'
        f'False positive verification_results: {fp_results}\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
