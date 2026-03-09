#!/usr/bin/env python3
"""Verifier for annual_policy_review_cycle task.

Scoring (100 pts total, pass >= 60):
  - >=5 new security policies (7 pts each):                 35 pts
  - New policies: >=2 Approved AND >=2 Draft:               15 pts
  - >=3 new IT asset records:                               20 pts
  - >=3 new policy exceptions:                              20 pts
  - Project with 'Policy' or 'Audit' in title:             10 pts

Baseline counts read from /tmp/annual_policy_review_cycle_baseline.txt.
Pre-seeded: 2 policies (both Approved), 0 assets, 0 exceptions, 0 projects.
"""


def _parse_baseline(raw):
    baseline = {}
    for line in (raw or '').strip().split('\n'):
        if '=' in line:
            k, v = line.split('=', 1)
            try:
                baseline[k.strip()] = int(v.strip())
            except ValueError:
                baseline[k.strip()] = 0
    return baseline


def _query_int(exec_in_env, sql):
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"' + sql + '" 2>/dev/null'
    )
    if result and result.strip().isdigit():
        return int(result.strip())
    return 0


def verify_annual_policy_review_cycle(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    # Load baseline
    raw = exec_in_env('cat /tmp/annual_policy_review_cycle_baseline.txt 2>/dev/null') or ''
    baseline = _parse_baseline(raw)
    b_policies = baseline.get('BASELINE_POLICIES', 2)
    b_approved = baseline.get('BASELINE_APPROVED_POLICIES', 2)
    b_draft = baseline.get('BASELINE_DRAFT_POLICIES', 0)
    b_assets = baseline.get('BASELINE_ASSETS', 0)
    b_exceptions = baseline.get('BASELINE_EXCEPTIONS', 0)
    b_projects = baseline.get('BASELINE_PROJECTS', 0)

    score = 0
    feedback_parts = []

    # --- Criterion 1: >=5 new security policies (35 pts, 7 each) ---
    cur_policies = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_policies WHERE deleted=0;')
    new_policies = max(0, cur_policies - b_policies)
    if new_policies >= 5:
        policy_pts = 35
    elif new_policies == 4:
        policy_pts = 28
    elif new_policies == 3:
        policy_pts = 21
    elif new_policies == 2:
        policy_pts = 14
    elif new_policies == 1:
        policy_pts = 7
    else:
        policy_pts = 0
    score += policy_pts
    if new_policies >= 5:
        feedback_parts.append(f"PASS: {new_policies} new security policies created ({policy_pts}/35 pts)")
    else:
        feedback_parts.append(f"PARTIAL: {new_policies}/5 new security policies ({policy_pts}/35 pts)")

    # --- Criterion 2: New policies include >=2 Approved AND >=2 Draft (15 pts) ---
    cur_approved = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_policies WHERE status=1 AND deleted=0;')
    cur_draft = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_policies WHERE status=0 AND deleted=0;')
    new_approved = max(0, cur_approved - b_approved)
    new_draft = max(0, cur_draft - b_draft)

    has_approved = new_approved >= 2
    has_draft = new_draft >= 2

    if has_approved and has_draft:
        score += 15
        feedback_parts.append(f"PASS: Policy mix: {new_approved} new Approved, {new_draft} new Draft (15/15 pts)")
    elif has_approved or has_draft:
        score += 7
        approved_str = f"{new_approved} Approved" if has_approved else f"{new_approved} Approved (need 2)"
        draft_str = f"{new_draft} Draft" if has_draft else f"{new_draft} Draft (need 2)"
        feedback_parts.append(f"PARTIAL: Policy mix: {approved_str}, {draft_str} (7/15 pts)")
    else:
        feedback_parts.append(f"FAIL: Insufficient policy status mix: {new_approved} new Approved, {new_draft} new Draft (need >=2 each) (0/15 pts)")

    # --- Criterion 3: >=3 new IT asset records (20 pts) ---
    cur_assets = _query_int(exec_in_env, 'SELECT COUNT(*) FROM assets;')
    new_assets = max(0, cur_assets - b_assets)
    if new_assets >= 3:
        score += 20
        feedback_parts.append(f"PASS: {new_assets} new IT assets registered (20/20 pts)")
    elif new_assets == 2:
        score += 13
        feedback_parts.append(f"PARTIAL: {new_assets}/3 new IT assets registered (13/20 pts)")
    elif new_assets == 1:
        score += 6
        feedback_parts.append(f"PARTIAL: {new_assets}/3 new IT assets registered (6/20 pts)")
    else:
        feedback_parts.append("FAIL: No new IT assets registered (0/20 pts)")

    # --- Criterion 4: >=3 new policy exceptions (20 pts) ---
    cur_exceptions = _query_int(exec_in_env, 'SELECT COUNT(*) FROM policy_exceptions;')
    new_exceptions = max(0, cur_exceptions - b_exceptions)
    if new_exceptions >= 3:
        score += 20
        feedback_parts.append(f"PASS: {new_exceptions} policy exceptions documented (20/20 pts)")
    elif new_exceptions == 2:
        score += 13
        feedback_parts.append(f"PARTIAL: {new_exceptions}/3 policy exceptions documented (13/20 pts)")
    elif new_exceptions == 1:
        score += 6
        feedback_parts.append(f"PARTIAL: {new_exceptions}/3 policy exceptions documented (6/20 pts)")
    else:
        feedback_parts.append("FAIL: No new policy exceptions found (0/20 pts)")

    # --- Criterion 5: Project with 'Policy' or 'Audit' in title (10 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM projects WHERE ('
        'title LIKE \'%Policy%\' OR title LIKE \'%policy%\' OR '
        'title LIKE \'%Audit%\' OR title LIKE \'%audit%\''
        ') AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    cur_projects = _query_int(exec_in_env, 'SELECT COUNT(*) FROM projects WHERE deleted=0;')
    new_projects = max(0, cur_projects - b_projects)
    if result and result.strip():
        score += 10
        feedback_parts.append("PASS: Policy/Audit review project found (10/10 pts)")
    elif new_projects >= 1:
        score += 5
        feedback_parts.append("PARTIAL: A project was created but title doesn't contain 'Policy' or 'Audit' (5/10 pts)")
    else:
        feedback_parts.append("FAIL: No policy review project found (0/10 pts)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }
