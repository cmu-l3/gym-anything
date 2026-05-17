#!/usr/bin/env python3
"""Verifier for restructure_division_merger.

Scoring (100 pts, pass >= 60):

  C1 (30 pts): All three LTP employees transferred to R&D — 10 pts each.
               Partial: 10 pts per employee correctly in R&D.

  C2 (20 pts): Correct job assignments — Ernest Reed = Senior Developer (10 pts),
               Randall Lewis = Project Lead (10 pts).
               Partial: 10 pts per correct job.

  C3 (15 pts): Paul Williams has Ernest Reed set as his Coach.

  C4 (20 pts): Ronnie Hart is R&D department manager.

  C5 (15 pts): Long Term Projects department is archived (active = False).

Anti-Pattern 4 audit:
  max_partial_total = 20 (C1, 2/3) + 10 (C2, 1 job) + 0 + 0 + 0 = 30 < 60  ✓
"""

import json
import os
import tempfile


def verify_restructure_division_merger(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env') if env_info else None
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env unavailable'}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/restructure_merger_result.json', tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Result read failed: {e}'}
    finally:
        try: os.unlink(tmp.name)
        except: pass

    if 'error' in result:
        return {'passed': False, 'score': 0, 'feedback': f"Export error: {result['error']}"}

    gt     = result.get('gt', {})
    ernest = result.get('ernest', {})
    paul   = result.get('paul',   {})
    randall= result.get('randall',{})
    rnd_id = gt.get('rnd_dept_id')
    ltp_id = gt.get('ltp_dept_id')

    score = 0
    fb = []

    # C1: All three employees in R&D
    for label, emp in [('Ernest Reed', ernest), ('Paul Williams', paul), ('Randall Lewis', randall)]:
        if emp.get('dept_id') == rnd_id:
            score += 10
            fb.append(f'{label} in R&D (+10)')
        else:
            fb.append(f'{label} dept={emp.get("dept_name","unknown")} (not R&D, +0)')

    # C2: Correct job assignments
    senior_dev_id  = gt.get('senior_dev_id')
    project_lead_id = gt.get('project_lead_id')

    if senior_dev_id is not None and ernest.get('job_id') == senior_dev_id:
        score += 10
        fb.append('Ernest Reed job=Senior Developer (+10)')
    else:
        fb.append(f'Ernest Reed job={ernest.get("job_name","?")} (expected Senior Developer, +0)')

    if project_lead_id is not None and randall.get('job_id') == project_lead_id:
        score += 10
        fb.append('Randall Lewis job=Project Lead (+10)')
    else:
        fb.append(f'Randall Lewis job={randall.get("job_name","?")} (expected Project Lead, +0)')

    # C3: Paul Williams has Ernest Reed as coach
    ernest_id_gt = gt.get('ernest_id')
    if ernest_id_gt is not None and paul.get('coach_id') == ernest_id_gt:
        score += 15
        fb.append('Paul Williams coach=Ernest Reed (+15)')
    else:
        fb.append(f'Paul Williams coach_id={paul.get("coach_id")} (expected Ernest Reed id={ernest_id_gt}, +0)')

    # C4: Ronnie Hart is R&D department manager
    ronnie_id = gt.get('ronnie_id')
    if ronnie_id is not None and result.get('rnd_dept_manager_id') == ronnie_id:
        score += 20
        fb.append('Ronnie Hart is R&D dept manager (+20)')
    else:
        fb.append(f'R&D manager={result.get("rnd_dept_manager_name","none")} (expected Ronnie Hart, +0)')

    # C5: LTP dept archived
    if result.get('ltp_active') is False:
        score += 15
        fb.append('Long Term Projects dept archived (+15)')
    else:
        fb.append('Long Term Projects dept still active (+0)')

    return {
        'passed': score >= 60,
        'score':  min(score, 100),
        'feedback': '; '.join(fb),
    }
