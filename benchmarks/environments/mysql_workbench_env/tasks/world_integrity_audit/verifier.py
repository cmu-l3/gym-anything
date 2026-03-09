#!/usr/bin/env python3
"""Verifier for world_integrity_audit task.

A very_hard DBA task: discover and fix multiple types of data quality issues
in the world database (orphaned records, zero-population entries, duplicates),
then export clean South American city data.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_world_integrity_audit(traj, env_info, task_info):
    """
    Verify world database integrity audit task completion.

    Scoring (100 points):
    - All ZZZ orphan cities removed (35 records): 25 pts
    - All ZZX orphan cities removed (10 records): 15 pts
    - All zero-population cities removed (8 records): 15 pts
    - Duplicate city records removed: 15 pts
    - South America CSV export matches current DB, >= 400 rows: 30 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/world_audit_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []

    # Criterion 1: ZZZ orphan cities removed (25 pts)
    zzz_remaining = result.get('zzz_remaining', 999)
    zzz_initial = result.get('zzz_initial', 35)
    if zzz_remaining == 0:
        score += 25
        feedback_parts.append(f"All {zzz_initial} ZZZ orphan cities removed (25/25)")
    elif zzz_remaining < zzz_initial:
        partial = int(25 * (zzz_initial - zzz_remaining) / max(zzz_initial, 1))
        score += partial
        feedback_parts.append(f"Partial ZZZ cleanup: {zzz_remaining} of {zzz_initial} remain ({partial}/25)")
    else:
        feedback_parts.append(f"ZZZ orphan cities NOT removed: {zzz_remaining} remain (0/25)")

    # Criterion 2: ZZX orphan cities removed (15 pts)
    zzx_remaining = result.get('zzx_remaining', 999)
    zzx_initial = result.get('zzx_initial', 10)
    if zzx_remaining == 0:
        score += 15
        feedback_parts.append(f"All {zzx_initial} ZZX orphan cities removed (15/15)")
    elif zzx_remaining < zzx_initial:
        partial = int(15 * (zzx_initial - zzx_remaining) / max(zzx_initial, 1))
        score += partial
        feedback_parts.append(f"Partial ZZX cleanup: {zzx_remaining} of {zzx_initial} remain ({partial}/15)")
    else:
        feedback_parts.append(f"ZZX orphan cities NOT removed: {zzx_remaining} remain (0/15)")

    # Criterion 3: Zero-population cities removed (15 pts)
    zero_remaining = result.get('zero_pop_remaining', 999)
    zero_initial = result.get('zero_pop_initial', 8)
    if zero_remaining == 0:
        score += 15
        feedback_parts.append(f"All zero-population cities removed (15/15)")
    elif zero_remaining < zero_initial:
        partial = int(15 * (zero_initial - zero_remaining) / max(zero_initial, 1))
        score += partial
        feedback_parts.append(f"Partial zero-population cleanup: {zero_remaining} remain ({partial}/15)")
    else:
        feedback_parts.append(f"Zero-population cities NOT removed: {zero_remaining} remain (0/15)")

    # Criterion 4: Duplicate records removed (15 pts)
    dupes_remaining = result.get('duplicate_count_remaining', 999)
    if dupes_remaining == 0:
        score += 15
        feedback_parts.append("All duplicate city records removed (15/15)")
    elif dupes_remaining < 3:
        score += 8
        feedback_parts.append(f"Partial duplicate removal: {dupes_remaining} duplicate rows remain (8/15)")
    else:
        feedback_parts.append(f"Duplicate records NOT removed: {dupes_remaining} extra rows remain (0/15)")

    # Criterion 5: South America CSV export (30 pts)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    sa_expected = result.get('sa_city_count_expected', 0)
    sa_current = result.get('sa_city_count_current', 0)

    if csv_exists and int(csv_mtime) > task_start:
        if csv_rows >= 400:
            # Check if CSV row count roughly matches what's in the DB after cleanup
            if sa_expected > 0 and abs(csv_rows - sa_current) <= 5:
                score += 30
                feedback_parts.append(f"SA cities CSV: {csv_rows} rows, matches DB count of {sa_current} (30/30)")
            elif csv_rows >= 400:
                score += 20
                feedback_parts.append(f"SA cities CSV: {csv_rows} rows (count differs from DB {sa_current}) (20/30)")
        elif csv_rows >= 100:
            score += 10
            feedback_parts.append(f"SA cities CSV created but only {csv_rows} rows (10/30)")
        else:
            score += 5
            feedback_parts.append(f"SA cities CSV exists but too few rows: {csv_rows} (5/30)")
    elif csv_exists:
        score += 5
        feedback_parts.append(f"SA cities CSV exists but may be pre-existing ({csv_rows} rows) (5/30)")
    else:
        feedback_parts.append("SA cities CSV NOT created (0/30)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
