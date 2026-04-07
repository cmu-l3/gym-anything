#!/usr/bin/env python3
"""
Verifier for brownfield_groundwater_exceedance_audit task.

Checks that the agent identified 11 monitoring wells marked 'BELOW_CLEANUP_LEVEL'
that actually exceed EPA Maximum Contaminant Levels (MCLs) under 40 CFR Part 141
and CERCLA cleanup standards.

EPA MCL values (µg/L = ppb):
  TCE (trichloroethylene):    5.0 µg/L
  PCE (tetrachloroethylene):  5.0 µg/L
  Benzene:                    5.0 µg/L
  Arsenic:                   10.0 µg/L
  Lead:                      15.0 µg/L
  Vinyl chloride:             2.0 µg/L
  1,2-DCE:                  70.0 µg/L

Contaminated wells (seeded as BELOW_CLEANUP_LEVEL but exceeding MCL):
  MW-001: TCE=8.5 µg/L (> 5 MCL)
  MW-002: PCE=7.8 µg/L (> 5 MCL)
  MW-003: benzene=8.9 µg/L (> 5 MCL)
  MW-004: arsenic=14.5 µg/L (> 10 MCL)
  MW-005: lead=22.0 µg/L (> 15 MCL)
  MW-006: TCE=6.2 µg/L (> 5 MCL)
  MW-007: vinyl_chloride=3.5 µg/L (> 2 MCL)
  MW-008: PCE=6.4 µg/L + DCE=85.0 µg/L (both exceed MCL)
  MW-009: TCE=9.8 µg/L (> 5 MCL)
  MW-010: benzene=6.7 µg/L (> 5 MCL)
  MW-011: arsenic=11.5 µg/L (> 10 MCL)

Scoring (100 pts total):
  - Each exceedance well correctly changed to EXCEEDS_CLEANUP_LEVEL: 7 pts × 11 = 77 pts
  - Each corrected well with non-empty exceedance_note: 1 pt × 11 = 11 pts
  - False positives (below-MCL wells wrongly changed): -6 pts each
  - Bonus: all 11 corrected with zero false positives: +12 pts
Pass threshold: 60 pts
"""

import sqlite3
import tempfile
import os

CONTAMINATED_WELL_IDS = [
    'MW-001', 'MW-002', 'MW-003', 'MW-004', 'MW-005',
    'MW-006', 'MW-007', 'MW-008', 'MW-009', 'MW-010', 'MW-011',
]

# EPA MCL values (µg/L)
EPA_MCL = {
    'TCE_ug_L': 5.0,
    'PCE_ug_L': 5.0,
    'benzene_ug_L': 5.0,
    'arsenic_ug_L': 10.0,
    'lead_ug_L': 15.0,
    'vinyl_chloride_ug_L': 2.0,
    'DCE_ug_L': 70.0,
}

POINTS_PER_STATUS = 7
POINTS_PER_NOTE = 1
FALSE_POSITIVE_PENALTY = 6
BONUS_ALL_CORRECT = 12
PASS_THRESHOLD = 60


def _well_exceeds_mcl(row):
    """Return True if any contaminant in this well exceeds its EPA MCL."""
    return (
        (row['TCE_ug_L'] is not None and row['TCE_ug_L'] > EPA_MCL['TCE_ug_L'])
        or (row['PCE_ug_L'] is not None and row['PCE_ug_L'] > EPA_MCL['PCE_ug_L'])
        or (row['benzene_ug_L'] is not None and row['benzene_ug_L'] > EPA_MCL['benzene_ug_L'])
        or (row['arsenic_ug_L'] is not None and row['arsenic_ug_L'] > EPA_MCL['arsenic_ug_L'])
        or (row['lead_ug_L'] is not None and row['lead_ug_L'] > EPA_MCL['lead_ug_L'])
        or (row['vinyl_chloride_ug_L'] is not None and row['vinyl_chloride_ug_L'] > EPA_MCL['vinyl_chloride_ug_L'])
        or (row['DCE_ug_L'] is not None and row['DCE_ug_L'] > EPA_MCL['DCE_ug_L'])
    )


def _get_exceedance_summary(row):
    """Return a string summarizing which contaminants exceed MCL."""
    exceedances = []
    if row['TCE_ug_L'] and row['TCE_ug_L'] > EPA_MCL['TCE_ug_L']:
        exceedances.append(f"TCE={row['TCE_ug_L']}µg/L (MCL={EPA_MCL['TCE_ug_L']})")
    if row['PCE_ug_L'] and row['PCE_ug_L'] > EPA_MCL['PCE_ug_L']:
        exceedances.append(f"PCE={row['PCE_ug_L']}µg/L (MCL={EPA_MCL['PCE_ug_L']})")
    if row['benzene_ug_L'] and row['benzene_ug_L'] > EPA_MCL['benzene_ug_L']:
        exceedances.append(f"benzene={row['benzene_ug_L']}µg/L (MCL={EPA_MCL['benzene_ug_L']})")
    if row['arsenic_ug_L'] and row['arsenic_ug_L'] > EPA_MCL['arsenic_ug_L']:
        exceedances.append(f"arsenic={row['arsenic_ug_L']}µg/L (MCL={EPA_MCL['arsenic_ug_L']})")
    if row['lead_ug_L'] and row['lead_ug_L'] > EPA_MCL['lead_ug_L']:
        exceedances.append(f"lead={row['lead_ug_L']}µg/L (MCL={EPA_MCL['lead_ug_L']})")
    if row['vinyl_chloride_ug_L'] and row['vinyl_chloride_ug_L'] > EPA_MCL['vinyl_chloride_ug_L']:
        exceedances.append(f"vinyl_chloride={row['vinyl_chloride_ug_L']}µg/L (MCL={EPA_MCL['vinyl_chloride_ug_L']})")
    if row['DCE_ug_L'] and row['DCE_ug_L'] > EPA_MCL['DCE_ug_L']:
        exceedances.append(f"DCE={row['DCE_ug_L']}µg/L (MCL={EPA_MCL['DCE_ug_L']})")
    return ', '.join(exceedances)


def check_brownfield_groundwater_exceedance_audit(traj, env_info, task_info):
    """
    Pull the modified GeoPackage from the Android device and verify that
    monitoring wells exceeding EPA MCL have been updated to EXCEEDS_CLEANUP_LEVEL.
    """
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/brownfield_groundwater_exceedance_audit_result.gpkg'
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
            "SELECT well_id, compliance_status, exceedance_note, "
            "TCE_ug_L, PCE_ug_L, benzene_ug_L, arsenic_ug_L, "
            "lead_ug_L, vinyl_chloride_ug_L, DCE_ug_L "
            "FROM monitoring_wells"
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
            'feedback': 'No wells found in monitoring_wells table.'
        }

    well_data = {row['well_id']: row for row in rows}

    score = 0
    details = []
    false_positives = 0
    contaminated_caught = 0

    for wid in CONTAMINATED_WELL_IDS:
        if wid not in well_data:
            details.append(f'MISS  {wid}: not found in layer')
            continue

        row = well_data[wid]
        current_status = (row['compliance_status'] or '').strip().upper()
        current_note = (row['exceedance_note'] or '').strip()

        if current_status == 'EXCEEDS_CLEANUP_LEVEL':
            score += POINTS_PER_STATUS
            contaminated_caught += 1
            details.append(f'PASS  {wid}: correctly changed to EXCEEDS_CLEANUP_LEVEL (+{POINTS_PER_STATUS}pts)')
        elif current_status == 'BELOW_CLEANUP_LEVEL':
            summary = _get_exceedance_summary(row)
            details.append(
                f'FAIL  {wid}: still BELOW_CLEANUP_LEVEL — '
                f'exceedances: {summary}'
            )
        else:
            details.append(f'PARTIAL  {wid}: status={current_status} (expected EXCEEDS_CLEANUP_LEVEL)')

        if current_note:
            score += POINTS_PER_NOTE
            details.append(f'PASS  {wid}: exceedance_note present (+{POINTS_PER_NOTE}pts): "{current_note[:80]}"')
        else:
            details.append(f'FAIL  {wid}: exceedance_note is empty — identify which contaminant exceeds MCL')

    # Check background wells for false positives
    for wid, row in well_data.items():
        if wid in CONTAMINATED_WELL_IDS:
            continue
        current_status = (row['compliance_status'] or '').strip().upper()
        if current_status == 'EXCEEDS_CLEANUP_LEVEL':
            if not _well_exceeds_mcl(row):
                false_positives += 1
                score -= FALSE_POSITIVE_PENALTY
                details.append(
                    f'FALSE_POSITIVE  {wid}: changed to EXCEEDS_CLEANUP_LEVEL '
                    f'but all contaminants are below EPA MCL (-{FALSE_POSITIVE_PENALTY}pts)'
                )

    if contaminated_caught == len(CONTAMINATED_WELL_IDS) and false_positives == 0:
        score += BONUS_ALL_CORRECT
        details.append(
            f'BONUS: All {len(CONTAMINATED_WELL_IDS)} exceedance wells '
            f'corrected with zero false positives (+{BONUS_ALL_CORRECT}pts)'
        )

    score = max(0, score)
    passed = score >= PASS_THRESHOLD
    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        f'MCL exceedance wells corrected: {contaminated_caught}/{len(CONTAMINATED_WELL_IDS)}\n'
        f'False positives: {false_positives}\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
