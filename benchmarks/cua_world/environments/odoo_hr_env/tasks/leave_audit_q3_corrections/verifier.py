#!/usr/bin/env python3
"""Verifier for leave_audit_q3_corrections.

Scoring (100 pts, pass >= 65):

  C1 (25 pts): 'Paid Time Off' leave type has leave_validation_type == 'manager'.

  C2 (15 pts): Ernest Reed's flagged leave request is in 'refuse' state.

  C3 (15 pts): Ronnie Hart's flagged leave request is in 'refuse' state.

  C4 (25 pts): Eli Lambert has at least one validated (state='validate') Paid Time Off
               allocation with exactly 15 days.
               Partial (10 pts): allocation exists for Eli but not yet validated,
               or has wrong number of days.

  C5 (20 pts): Walter Horton's over-limit allocation has been reduced to <= 15 days.

Anti-Pattern 4 audit:
  max_partial_total = 10 (C4 partial only) = 10 < 65  ✓
  Do-nothing score = 0 (all wrong or absent at task start)  ✓
"""

import json
import os
import tempfile


def verify_leave_audit_q3_corrections(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env') if env_info else None
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env unavailable'}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/leave_audit_result.json', tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Result read failed: {e}'}
    finally:
        try: os.unlink(tmp.name)
        except: pass

    if 'error' in result:
        return {'passed': False, 'score': 0, 'feedback': f"Export error: {result['error']}"}

    score = 0
    fb = []

    # C1: PTO validation type
    pto_val = result.get('pto_validation_type', 'unknown')
    if pto_val == 'manager':
        score += 25
        fb.append('Paid Time Off validation=manager (+25)')
    else:
        fb.append(f'Paid Time Off validation={pto_val} (expected manager, +0)')

    # C2: Ernest leave refused
    ernest_state = result.get('ernest_leave_state', 'unknown')
    if ernest_state == 'refuse':
        score += 15
        fb.append('Ernest Reed leave refused (+15)')
    else:
        fb.append(f'Ernest Reed leave state={ernest_state} (not refused, +0)')

    # C3: Ronnie leave refused
    ronnie_state = result.get('ronnie_leave_state', 'unknown')
    if ronnie_state == 'refuse':
        score += 15
        fb.append('Ronnie Hart leave refused (+15)')
    else:
        fb.append(f'Ronnie Hart leave state={ronnie_state} (not refused, +0)')

    # C4: Eli Lambert allocation
    eli_allocs = result.get('eli_pto_allocations', [])
    validated_correct = [a for a in eli_allocs
                         if a.get('state') in ('validate','validate1')
                         and abs(a.get('number_of_days', 0) - 15) < 0.5]
    any_alloc = len(eli_allocs) > 0

    if validated_correct:
        score += 25
        fb.append(f'Eli Lambert: validated 15-day PTO allocation exists (+25)')
    elif any_alloc:
        score += 10
        best = eli_allocs[0]
        fb.append(f'Eli Lambert: allocation exists (state={best.get("state")}, '
                  f'days={best.get("number_of_days")}) but not fully correct (+10 partial)')
    else:
        fb.append('Eli Lambert: no PTO allocation found (+0)')

    # C5: Walter Horton allocation days
    walter_days = result.get('walter_alloc_days', 20)
    try:
        walter_days = float(walter_days)
    except (TypeError, ValueError):
        walter_days = 20.0

    if walter_days <= 15.0:
        score += 20
        fb.append(f'Walter Horton allocation reduced to {walter_days} days (+20)')
    else:
        fb.append(f'Walter Horton allocation still {walter_days} days (exceeds 15-day cap, +0)')

    return {
        'passed':   score >= 65,
        'score':    min(score, 100),
        'feedback': '; '.join(fb),
    }
