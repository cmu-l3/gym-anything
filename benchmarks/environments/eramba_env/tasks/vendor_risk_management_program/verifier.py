#!/usr/bin/env python3
"""Verifier for vendor_risk_management_program task.

Scoring (100 pts total, pass >= 60):
  - >=4 new third-party vendors (7.5 pts each):            30 pts
  - >=4 new risks with treatment strategies (7.5 pts each): 30 pts
  - 'Third-Party Risk Management Policy' (Approved):        20 pts
  - Project with 'Vendor' in title:                         10 pts
  - >=2 new policy exceptions:                              10 pts

Baseline counts read from /tmp/vendor_risk_management_program_baseline.txt.
Pre-seeded vendors: AWS, Salesforce (2 total).
Pre-seeded risks with treatment: Ransomware (Mitigate), Insider Threat (Accept) = 2.
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


def verify_vendor_risk_management_program(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    # Load baseline
    raw = exec_in_env('cat /tmp/vendor_risk_management_program_baseline.txt 2>/dev/null') or ''
    baseline = _parse_baseline(raw)
    b_third_parties = baseline.get('BASELINE_THIRD_PARTIES', 2)
    b_risks_with_treatment = baseline.get('BASELINE_RISKS_WITH_TREATMENT', 2)
    b_exceptions = baseline.get('BASELINE_EXCEPTIONS', 0)
    b_projects = baseline.get('BASELINE_PROJECTS', 0)
    b_policies = baseline.get('BASELINE_POLICIES', 2)

    score = 0
    feedback_parts = []

    # --- Criterion 1: >=4 new third-party vendors (30 pts, 7.5 each) ---
    cur_vendors = _query_int(exec_in_env, 'SELECT COUNT(*) FROM third_parties WHERE deleted=0;')
    new_vendors = max(0, cur_vendors - b_third_parties)
    # Progressive: 7 pts per vendor up to 4 (rounding to integers)
    if new_vendors >= 4:
        vendor_pts = 30
    elif new_vendors == 3:
        vendor_pts = 22
    elif new_vendors == 2:
        vendor_pts = 15
    elif new_vendors == 1:
        vendor_pts = 7
    else:
        vendor_pts = 0
    score += vendor_pts
    if new_vendors >= 4:
        feedback_parts.append(f"PASS: {new_vendors} new third-party vendors registered ({vendor_pts}/30 pts)")
    else:
        feedback_parts.append(f"PARTIAL: {new_vendors}/4 new vendors registered ({vendor_pts}/30 pts)")

    # --- Criterion 2: >=4 new risks with treatment strategies (30 pts, 7.5 each) ---
    cur_risks_with_treatment = _query_int(
        exec_in_env,
        'SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id IS NOT NULL AND deleted=0;'
    )
    new_risks_with_treatment = max(0, cur_risks_with_treatment - b_risks_with_treatment)
    if new_risks_with_treatment >= 4:
        risk_pts = 30
    elif new_risks_with_treatment == 3:
        risk_pts = 22
    elif new_risks_with_treatment == 2:
        risk_pts = 15
    elif new_risks_with_treatment == 1:
        risk_pts = 7
    else:
        risk_pts = 0
    score += risk_pts
    if new_risks_with_treatment >= 4:
        feedback_parts.append(f"PASS: {new_risks_with_treatment} new risks with treatment ({risk_pts}/30 pts)")
    else:
        feedback_parts.append(f"PARTIAL: {new_risks_with_treatment}/4 new risks with treatment ({risk_pts}/30 pts)")

    # --- Criterion 3: Third-Party Risk Management Policy (Approved) (20 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM security_policies WHERE ('
        '\\`index\\` LIKE \'%Third-Party%\' OR \\`index\\` LIKE \'%Third Party%\' OR '
        '\\`index\\` LIKE \'%Vendor%\' OR \\`index\\` LIKE \'%TPRM%\''
        ') AND status=1 AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    if result and result.strip():
        score += 20
        feedback_parts.append("PASS: Third-Party Risk Management Policy found with Approved status (20/20 pts)")
    else:
        # Partial: policy exists but wrong status
        result2 = exec_in_env(
            'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
            '"SELECT id FROM security_policies WHERE ('
            '\\`index\\` LIKE \'%Third-Party%\' OR \\`index\\` LIKE \'%Third Party%\' OR '
            '\\`index\\` LIKE \'%Vendor%\' OR \\`index\\` LIKE \'%TPRM%\''
            ') AND deleted=0 LIMIT 1;" 2>/dev/null'
        )
        cur_policies = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_policies WHERE deleted=0;')
        new_policies = max(0, cur_policies - b_policies)
        if result2 and result2.strip():
            score += 10
            feedback_parts.append("PARTIAL: TPRM/Vendor policy found but not Approved (10/20 pts)")
        elif new_policies >= 1:
            score += 5
            feedback_parts.append("PARTIAL: A new policy created but title doesn't match TPRM/Vendor (5/20 pts)")
        else:
            feedback_parts.append("FAIL: Third-Party Risk Management Policy not found (0/20 pts)")

    # --- Criterion 4: Project with 'Vendor' in title (10 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM projects WHERE (title LIKE \'%Vendor%\' OR title LIKE \'%vendor%\' OR title LIKE \'%TPRM%\') AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    cur_projects = _query_int(exec_in_env, 'SELECT COUNT(*) FROM projects WHERE deleted=0;')
    new_projects = max(0, cur_projects - b_projects)
    if result and result.strip():
        score += 10
        feedback_parts.append("PASS: Vendor assessment project found (10/10 pts)")
    elif new_projects >= 1:
        score += 5
        feedback_parts.append("PARTIAL: A project was created but title doesn't contain 'Vendor' (5/10 pts)")
    else:
        feedback_parts.append("FAIL: No vendor assessment project found (0/10 pts)")

    # --- Criterion 5: >=2 new policy exceptions (10 pts) ---
    cur_exceptions = _query_int(exec_in_env, 'SELECT COUNT(*) FROM policy_exceptions;')
    new_exceptions = max(0, cur_exceptions - b_exceptions)
    if new_exceptions >= 2:
        score += 10
        feedback_parts.append(f"PASS: {new_exceptions} vendor policy exceptions documented (10/10 pts)")
    elif new_exceptions == 1:
        score += 5
        feedback_parts.append("PARTIAL: 1/2 vendor policy exceptions documented (5/10 pts)")
    else:
        feedback_parts.append("FAIL: No vendor policy exceptions found (0/10 pts)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }
