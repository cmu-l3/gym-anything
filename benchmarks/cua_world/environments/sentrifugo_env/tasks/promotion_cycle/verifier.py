#!/usr/bin/env python3
"""
Verifier for promotion_cycle task.

The agent must:
  1. Create job title "Engineering Manager" (code ENG-MGR)
  2. Update 4 employees to their new titles per the promotion list

Expected post-promotion state:
  EMP001 James Anderson  → Engineering Manager
  EMP006 Jessica Liu     → Senior Software Engineer
  EMP012 Jennifer Martinez → Senior Data Scientist
  EMP019 Tyler Moore     → Sales Manager

Scoring (100 pts total, pass = 60):
  - Engineering Manager job title exists:  20 pts
  - EMP001 has Engineering Manager title:  20 pts
  - EMP006 has Senior Software Engineer:   20 pts
  - EMP012 has Senior Data Scientist:      20 pts
  - EMP019 has Sales Manager:              20 pts
  Total: 100 pts
"""

_DB_CMD = (
    "docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo "
    "-N -B -e \"{query}\""
)

_PASS_THRESHOLD = 70

_PROMOTIONS = [
    {'empid': 'EMP001', 'name': 'James Anderson',    'new_title': 'Engineering Manager'},
    {'empid': 'EMP006', 'name': 'Jessica Liu',        'new_title': 'Senior Software Engineer'},
    {'empid': 'EMP012', 'name': 'Jennifer Martinez',  'new_title': 'Senior Data Scientist'},
    {'empid': 'EMP019', 'name': 'Tyler Moore',        'new_title': 'Sales Manager'},
]


def _query_scalar(exec_env, sql):
    try:
        return exec_env(_DB_CMD.format(query=sql)).strip()
    except Exception:
        return ''


def verify_promotion_cycle(traj, env_info, task_info):
    exec_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if exec_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'exec_in_env not available in env_info'}

    score = 0
    feedback_parts = []

    # ---- Check Engineering Manager job title exists ----
    eng_mgr_count = _query_scalar(
        exec_env,
        "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Engineering Manager' AND isactive=1;"
    )
    if eng_mgr_count and int(eng_mgr_count) > 0:
        score += 20
        feedback_parts.append('Job title "Engineering Manager": created (20/20)')
    else:
        feedback_parts.append('Job title "Engineering Manager": not found (0/20)')

    # ---- Check each employee has their promoted title ----
    for promo in _PROMOTIONS:
        empid = promo['empid']
        expected_title = promo['new_title']

        actual_title = _query_scalar(
            exec_env,
            f"SELECT j.jobtitlename FROM main_users u "
            f"JOIN main_jobtitles j ON u.jobtitle_id = j.id "
            f"WHERE u.employeeId='{empid}' AND u.isactive=1 LIMIT 1;"
        )

        if actual_title == expected_title:
            score += 20
            feedback_parts.append(
                f'{empid} ({promo["name"]}): title correct — "{actual_title}" (20/20)')
        else:
            feedback_parts.append(
                f'{empid} ({promo["name"]}): title wrong — '
                f'got "{actual_title}", expected "{expected_title}" (0/20)')

    passed = score >= _PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': '; '.join(feedback_parts),
    }
