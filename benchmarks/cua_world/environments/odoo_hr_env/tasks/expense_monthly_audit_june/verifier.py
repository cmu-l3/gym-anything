#!/usr/bin/env python3
"""Verifier for expense_monthly_audit_june.

Scoring (100 pts, pass >= 65):

  C1 (20 pts): 'Conference Registration' product has can_be_expensed=True.

  C2 (20 pts): Eli Lambert's expense sheet state is 'approve', 'post', or 'done'.
               Partial: 10 pts if state is 'submit' (submitted but not approved).

  C3 (30 pts): Rachel Perry's expense sheet state is 'cancel' (refused).

  C4 (30 pts): Marc Demo's expense sheet state is 'cancel' (refused).

Anti-Pattern 4 audit:
  max_partial_total = 10 (C2 partial only) = 10 < 65  ✓
  Do-nothing score = 0 (conf still false, eli draft, rachel/marc still submitted)  ✓
"""

import json
import os
import tempfile


def verify_expense_monthly_audit_june(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env') if env_info else None
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env unavailable'}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/expense_audit_result.json', tmp.name)
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

    # C1: Conference Registration is now reimbursable
    if result.get('conf_can_be_expensed'):
        score += 20
        fb.append('Conference Registration marked as reimbursable (+20)')
    else:
        fb.append('Conference Registration still not reimbursable (+0)')

    # C2: Eli Lambert sheet approved (with partial for submitted)
    eli_state = result.get('eli_sheet_state')
    if eli_state in ('approve', 'post', 'done'):
        score += 20
        fb.append(f'Eli Lambert sheet approved (state={eli_state}) (+20)')
    elif eli_state == 'submit':
        score += 10
        fb.append(f'Eli Lambert sheet submitted but not yet approved (+10 partial)')
    else:
        fb.append(f'Eli Lambert sheet not processed (state={eli_state}) (+0)')

    # C3: Rachel Perry sheet refused
    rachel_state = result.get('rachel_sheet_state')
    if rachel_state == 'cancel':
        score += 30
        fb.append('Rachel Perry over-cap sheet refused (+30)')
    else:
        fb.append(f'Rachel Perry sheet not refused (state={rachel_state}) (+0)')

    # C4: Marc Demo sheet refused
    marc_state = result.get('marc_sheet_state')
    if marc_state == 'cancel':
        score += 30
        fb.append('Marc Demo duplicate-claim sheet refused (+30)')
    else:
        fb.append(f'Marc Demo sheet not refused (state={marc_state}) (+0)')

    return {
        'passed':   score >= 65,
        'score':    min(score, 100),
        'feedback': '; '.join(fb),
    }
