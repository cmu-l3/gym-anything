#!/usr/bin/env python3
"""
Verifier for wildlife_species_audit task.

Checks that the agent:
1. Corrected IUCN conservation_status for Grus americana (EN), Bubo scandiacus (VU),
   Charadrius melodus (NT), and Limosa fedoa (NT) — all were seeded as LC (wrong).
2. Added a non-empty priority_note for each NT/VU/EN/CR species record.

Scoring (total 100 pts):
  - Each correctly updated status:  15 pts each × 4 = 60 pts
  - Each non-empty priority_note for that species: 10 pts each × 4 = 40 pts
Pass threshold: 60 pts (all 4 statuses corrected, with or without notes)
"""

import sqlite3
import tempfile
import os


# IUCN Red List 2023 correct statuses for the seeded wrong-status species
CORRECT_STATUSES = {
    'Grus americana': 'EN',
    'Bubo scandiacus': 'VU',
    'Charadrius melodus': 'NT',
    'Limosa fedoa': 'NT',
}

POINTS_PER_STATUS = 15
POINTS_PER_NOTE = 10
PASS_THRESHOLD = 60


def check_wildlife_species_audit(traj, env_info, task_info):
    """
    Pull the modified GeoPackage from the Android device and check conservation
    status corrections and priority notes.
    """
    result_path = task_info.get('metadata', {}).get(
        'result_file',
        '/sdcard/wildlife_species_audit_result.gpkg'
    )

    tmp = tempfile.mktemp(suffix='.gpkg')
    try:
        env_info['copy_from_env'](result_path, tmp)
    except (FileNotFoundError, KeyError, Exception) as e:
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

        # Check all 4 target species
        rows = conn.execute(
            "SELECT species_name, conservation_status, priority_note "
            "FROM species_observations "
            "WHERE species_name IN (?, ?, ?, ?)",
            tuple(CORRECT_STATUSES.keys())
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
            'feedback': (
                'No target species found in species_observations table. '
                'Table may be missing or layer was not opened.'
            )
        }

    score = 0
    details = []

    # Map species → current DB values (aggregate if duplicates)
    species_data = {}
    for row in rows:
        sp = row['species_name']
        status = (row['conservation_status'] or '').strip().upper()
        note = (row['priority_note'] or '').strip()
        if sp not in species_data:
            species_data[sp] = {'status': status, 'note': note}
        else:
            # Take the most-recent (or best) value if duplicates exist
            if status == CORRECT_STATUSES[sp]:
                species_data[sp]['status'] = status
            if note:
                species_data[sp]['note'] = note

    for sp, correct_status in CORRECT_STATUSES.items():
        if sp not in species_data:
            details.append(f'MISS  {sp}: not found in layer (species may not have been opened)')
            continue

        current = species_data[sp]
        current_status = current['status']
        current_note = current['note']

        if current_status == correct_status:
            score += POINTS_PER_STATUS
            details.append(f'PASS  {sp}: status correctly set to {correct_status} (+{POINTS_PER_STATUS}pts)')
        elif current_status == 'LC' and correct_status != 'LC':
            details.append(
                f'FAIL  {sp}: status still LC (wrong) — expected {correct_status}. '
                'Check IUCN Red List 2023 for this species.'
            )
        else:
            details.append(
                f'PARTIAL  {sp}: status changed to {current_status} but expected {correct_status}'
            )

        if current_note:
            score += POINTS_PER_NOTE
            details.append(f'PASS  {sp}: priority_note present (+{POINTS_PER_NOTE}pts): "{current_note[:60]}"')
        else:
            details.append(f'FAIL  {sp}: priority_note is empty — NT/VU/EN species require monitoring note')

    passed = score >= PASS_THRESHOLD
    feedback = (
        f'Score: {score}/100 (pass threshold: {PASS_THRESHOLD})\n'
        + '\n'.join(details)
    )

    return {'passed': passed, 'score': score, 'feedback': feedback}
