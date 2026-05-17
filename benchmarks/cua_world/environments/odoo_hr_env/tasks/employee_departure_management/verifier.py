#!/usr/bin/env python3
"""Verifier for employee_departure_management.

Scoring (100 pts, pass >= 65):

  C1a (15 pts): Rachel Perry's parent_id is no longer Tina Williamson.

  C1b (10 pts): Doris Cole's parent_id is no longer Tina Williamson.

  C2  (20 pts): Tina's submitted expense sheet state is 'cancel' (refused).

  C3  (30 pts): Tina Williamson is archived (active=False).

  C4  (15 pts): Tina's departure_reason_id is set (not null).

  C5  (10 pts): A chatter message on Tina's employee record references leave/PTO/balance.

Anti-Pattern 4 audit:
  max_partial_total = 15 (C1a only) = 15 < 65  ✓
  Do-nothing score = 0 (Tina active, direct reports unchanged, sheet submitted)  ✓
"""

import json
import os
import tempfile


def verify_employee_departure_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env') if env_info else None
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env unavailable'}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/departure_mgmt_result.json', tmp.name)
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

    # C1a: Rachel Perry reassigned
    if result.get('rachel_reassigned'):
        score += 15
        fb.append('Rachel Perry reassigned to new manager (+15)')
    else:
        fb.append('Rachel Perry still reports to departing manager (+0)')

    # C1b: Doris Cole reassigned
    if result.get('doris_reassigned'):
        score += 10
        fb.append('Doris Cole reassigned to new manager (+10)')
    else:
        fb.append('Doris Cole still reports to departing manager (+0)')

    # C2: Expense sheet refused
    sheet_state = result.get('tina_sheet_state')
    if sheet_state == 'cancel':
        score += 20
        fb.append('Tina expense sheet refused (+20)')
    else:
        fb.append(f'Tina expense sheet not refused (state={sheet_state}) (+0)')

    # C3: Tina archived
    if not result.get('tina_active', True):
        score += 30
        fb.append('Tina Williamson archived (active=False) (+30)')
    else:
        fb.append('Tina Williamson still active (+0)')

    # C4: Departure reason set
    if result.get('departure_reason_id'):
        score += 15
        fb.append(f'Departure reason recorded (id={result["departure_reason_id"]}) (+15)')
    else:
        fb.append('Departure reason not set (+0)')

    # C5: Leave/balance note in chatter
    if result.get('leave_note_found'):
        score += 10
        fb.append('Chatter note referencing leave/PTO balance found (+10)')
    else:
        fb.append('No chatter note about leave balance (+0)')

    return {
        'passed':   score >= 65,
        'score':    min(score, 100),
        'feedback': '; '.join(fb),
    }
