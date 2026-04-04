#!/usr/bin/env python3
"""Verifier for hipaa_risk_treatment_program task.

Scoring (100 pts total, pass >= 60):
  - >=5 new risks with treatment strategies set:   40 pts (8 per risk)
  - >=3 new internal controls (security services): 20 pts
  - HIPAA Security Rule Compliance Policy Approved: 20 pts
  - Project with 'HIPAA' in title:                 10 pts
  - >=2 new policy exceptions:                     10 pts

Baseline counts are read from /tmp/hipaa_risk_treatment_program_baseline.txt
(written by setup_task.sh) to distinguish new records from pre-seeded ones.
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


def verify_hipaa_risk_treatment_program(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    # Load baseline
    raw = exec_in_env('cat /tmp/hipaa_risk_treatment_program_baseline.txt 2>/dev/null') or ''
    baseline = _parse_baseline(raw)
    b_risks_with_treatment = baseline.get('BASELINE_RISKS_WITH_TREATMENT', 2)
    b_services = baseline.get('BASELINE_SERVICES', 2)
    b_exceptions = baseline.get('BASELINE_EXCEPTIONS', 0)
    b_projects = baseline.get('BASELINE_PROJECTS', 0)

    score = 0
    feedback_parts = []

    # --- Criterion 1: >=5 new risks with treatment strategies set (40 pts) ---
    cur_risks_with_treatment = _query_int(
        exec_in_env,
        'SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id IS NOT NULL AND deleted=0;'
    )
    new_risks_with_treatment = max(0, cur_risks_with_treatment - b_risks_with_treatment)
    pts = min(5, new_risks_with_treatment) * 8
    score += pts
    if new_risks_with_treatment >= 5:
        feedback_parts.append(f"PASS: {new_risks_with_treatment} new risks with treatment strategies ({pts}/40 pts)")
    else:
        feedback_parts.append(f"PARTIAL: {new_risks_with_treatment}/5 new risks with treatment strategies ({pts}/40 pts)")

    # --- Criterion 2: >=3 new internal controls / security services (20 pts) ---
    cur_services = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_services WHERE deleted=0;')
    new_services = max(0, cur_services - b_services)
    if new_services >= 3:
        score += 20
        feedback_parts.append(f"PASS: {new_services} new internal controls (20/20 pts)")
    elif new_services >= 1:
        svc_pts = new_services * 6
        score += svc_pts
        feedback_parts.append(f"PARTIAL: {new_services}/3 new internal controls ({svc_pts}/20 pts)")
    else:
        feedback_parts.append("FAIL: No new internal controls found (0/20 pts)")

    # --- Criterion 3: HIPAA Security Rule Compliance Policy with Approved status (20 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM security_policies WHERE (\\`index\\` LIKE \'%HIPAA%\') AND status=1 AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    if result and result.strip():
        score += 20
        feedback_parts.append("PASS: HIPAA policy found with Approved status (20/20 pts)")
    else:
        # Partial credit: HIPAA policy exists but not Approved
        result2 = exec_in_env(
            'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
            '"SELECT id FROM security_policies WHERE (\\`index\\` LIKE \'%HIPAA%\') AND deleted=0 LIMIT 1;" 2>/dev/null'
        )
        if result2 and result2.strip():
            score += 10
            feedback_parts.append("PARTIAL: HIPAA policy found but not set to Approved status (10/20 pts)")
        else:
            feedback_parts.append("FAIL: HIPAA Security Rule Compliance Policy not found (0/20 pts)")

    # --- Criterion 4: Project with 'HIPAA' in title (10 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM projects WHERE title LIKE \'%HIPAA%\' AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    cur_projects = _query_int(exec_in_env, 'SELECT COUNT(*) FROM projects WHERE deleted=0;')
    new_projects = max(0, cur_projects - b_projects)
    if result and result.strip():
        score += 10
        feedback_parts.append("PASS: HIPAA project found (10/10 pts)")
    elif new_projects >= 1:
        score += 5
        feedback_parts.append("PARTIAL: A project was created but title does not contain 'HIPAA' (5/10 pts)")
    else:
        feedback_parts.append("FAIL: No HIPAA project found (0/10 pts)")

    # --- Criterion 5: >=2 new policy exceptions (10 pts) ---
    cur_exceptions = _query_int(exec_in_env, 'SELECT COUNT(*) FROM policy_exceptions;')
    new_exceptions = max(0, cur_exceptions - b_exceptions)
    if new_exceptions >= 2:
        score += 10
        feedback_parts.append(f"PASS: {new_exceptions} policy exceptions documented (10/10 pts)")
    elif new_exceptions == 1:
        score += 5
        feedback_parts.append("PARTIAL: 1/2 policy exceptions documented (5/10 pts)")
    else:
        feedback_parts.append("FAIL: No new policy exceptions found (0/10 pts)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }
