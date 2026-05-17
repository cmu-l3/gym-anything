#!/usr/bin/env python3
"""Verifier for recruitment_q2_pipeline_cleanup.

Scoring (100 pts, pass >= 65):

  C1 (25 pts): 'Technical Assessment' stage has a sequence strictly between
               'First Interview' and 'Second Interview'.

  C2 (15 pts): Cameron Foster's application is archived (active=False).

  C3 (20 pts): Thomas Weber duplicate resolved correctly:
               - SDS application (earlier stage) is archived (10 pts)
               - Experienced Developer application (more advanced) is still active (10 pts)
               Partial: 10 pts if only one side is correct.

  C4a (15 pts): Sofia Martinez's application is in the 'Contract Signed' stage.

  C4b (25 pts): Sofia Martinez has an employee record created (emp_id is set).

Anti-Pattern 4 audit:
  max_partial_total = 10 (C3 one-side) = 10 < 65  ✓
  Do-nothing score = 0 (all stages wrong, all applicants active at start)  ✓
"""

import json
import os
import tempfile


def verify_recruitment_q2_pipeline_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env') if env_info else None
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env unavailable'}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/recruitment_cleanup_result.json', tmp.name)
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

    first_seq  = result.get('first_interview_seq',  10)
    second_seq = result.get('second_interview_seq', 20)
    ta_seq     = result.get('ta_sequence')

    # C1: Technical Assessment repositioned
    if ta_seq is not None and first_seq < ta_seq < second_seq:
        score += 25
        fb.append(f'Technical Assessment seq={ta_seq} correctly between '
                  f'First Interview ({first_seq}) and Second Interview ({second_seq}) (+25)')
    else:
        fb.append(f'Technical Assessment seq={ta_seq} not between {first_seq}..{second_seq} (+0)')

    # C2: Cameron Foster archived
    if not result.get('cameron_active', True):
        score += 15
        fb.append('Cameron Foster archived (+15)')
    else:
        fb.append('Cameron Foster still active (+0)')

    # C3: Thomas Weber duplicate resolution
    sds_archived    = not result.get('thomas_sds_active',    True)
    expdev_active   =     result.get('thomas_expdev_active', True)
    if sds_archived and expdev_active:
        score += 20
        fb.append('Thomas Weber: SDS application archived, ExpDev application kept (+20)')
    elif sds_archived:
        score += 10
        fb.append('Thomas Weber: SDS application archived but ExpDev application also archived (+10 partial)')
    elif expdev_active and result.get('thomas_sds_active', True) is False:
        score += 10
        fb.append('Thomas Weber: ExpDev kept but SDS not yet archived (+10 partial)')
    else:
        fb.append('Thomas Weber: duplicate not resolved (+0)')

    # C4a: Sofia at Contract Signed
    if result.get('sofia_at_contract_signed'):
        score += 15
        fb.append('Sofia Martinez at Contract Signed (+15)')
    else:
        fb.append('Sofia Martinez not at Contract Signed (+0)')

    # C4b: Sofia employee created
    if result.get('sofia_hired'):
        score += 25
        fb.append(f'Sofia Martinez employee created (emp_id={result.get("sofia_emp_id")}) (+25)')
    else:
        fb.append('Sofia Martinez employee not created (+0)')

    return {
        'passed':   score >= 65,
        'score':    min(score, 100),
        'feedback': '; '.join(fb),
    }
