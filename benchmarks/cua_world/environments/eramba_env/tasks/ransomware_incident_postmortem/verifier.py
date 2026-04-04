#!/usr/bin/env python3
"""Verifier for ransomware_incident_postmortem task.

Scoring (100 pts total, pass >= 60):
  - Security incident with 'Ransomware' in title:         20 pts
  - >=3 new post-incident risks with treatment strategies: 20 pts
  - >=4 new internal controls (remediation controls):     25 pts
  - >=2 new policy exceptions:                            20 pts
  - Project with 'Recovery' or 'Ransomware' in title:     15 pts

Baseline counts read from /tmp/ransomware_incident_postmortem_baseline.txt.
Pre-seeded: 0 incidents, 3 risks (2 with treatment), 2 services, 0 exceptions, 0 projects.
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


def verify_ransomware_incident_postmortem(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    # Load baseline
    raw = exec_in_env('cat /tmp/ransomware_incident_postmortem_baseline.txt 2>/dev/null') or ''
    baseline = _parse_baseline(raw)
    b_incidents = baseline.get('BASELINE_INCIDENTS', 0)
    b_risks_with_treatment = baseline.get('BASELINE_RISKS_WITH_TREATMENT', 2)
    b_services = baseline.get('BASELINE_SERVICES', 2)
    b_exceptions = baseline.get('BASELINE_EXCEPTIONS', 0)
    b_projects = baseline.get('BASELINE_PROJECTS', 0)

    score = 0
    feedback_parts = []

    # --- Criterion 1: Security incident with 'Ransomware' in title (20 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM security_incidents WHERE (title LIKE \'%Ransomware%\' OR title LIKE \'%ransomware%\') LIMIT 1;" 2>/dev/null'
    )
    cur_incidents = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_incidents;')
    new_incidents = max(0, cur_incidents - b_incidents)
    if result and result.strip():
        score += 20
        feedback_parts.append("PASS: Ransomware incident documented (20/20 pts)")
    elif new_incidents >= 1:
        score += 10
        feedback_parts.append("PARTIAL: A security incident was created but title does not contain 'Ransomware' (10/20 pts)")
    else:
        feedback_parts.append("FAIL: No ransomware incident found (0/20 pts)")

    # --- Criterion 2: >=3 new post-incident risks with treatment (20 pts) ---
    cur_risks_with_treatment = _query_int(
        exec_in_env,
        'SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id IS NOT NULL AND deleted=0;'
    )
    new_risks_with_treatment = max(0, cur_risks_with_treatment - b_risks_with_treatment)
    if new_risks_with_treatment >= 3:
        score += 20
        feedback_parts.append(f"PASS: {new_risks_with_treatment} new risks with treatment strategies (20/20 pts)")
    elif new_risks_with_treatment == 2:
        score += 13
        feedback_parts.append(f"PARTIAL: {new_risks_with_treatment}/3 new risks with treatment strategies (13/20 pts)")
    elif new_risks_with_treatment == 1:
        score += 6
        feedback_parts.append(f"PARTIAL: {new_risks_with_treatment}/3 new risks with treatment strategies (6/20 pts)")
    else:
        feedback_parts.append("FAIL: No new post-incident risks found (0/20 pts)")

    # --- Criterion 3: >=4 new internal controls (25 pts) ---
    cur_services = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_services WHERE deleted=0;')
    new_services = max(0, cur_services - b_services)
    if new_services >= 4:
        score += 25
        feedback_parts.append(f"PASS: {new_services} new remediation controls created (25/25 pts)")
    elif new_services == 3:
        score += 18
        feedback_parts.append(f"PARTIAL: {new_services}/4 new remediation controls (18/25 pts)")
    elif new_services == 2:
        score += 12
        feedback_parts.append(f"PARTIAL: {new_services}/4 new remediation controls (12/25 pts)")
    elif new_services == 1:
        score += 6
        feedback_parts.append(f"PARTIAL: {new_services}/4 new remediation controls (6/25 pts)")
    else:
        feedback_parts.append("FAIL: No new remediation controls found (0/25 pts)")

    # --- Criterion 4: >=2 new policy exceptions (20 pts) ---
    cur_exceptions = _query_int(exec_in_env, 'SELECT COUNT(*) FROM policy_exceptions;')
    new_exceptions = max(0, cur_exceptions - b_exceptions)
    if new_exceptions >= 2:
        score += 20
        feedback_parts.append(f"PASS: {new_exceptions} emergency exception records documented (20/20 pts)")
    elif new_exceptions == 1:
        score += 10
        feedback_parts.append("PARTIAL: 1/2 emergency exception records documented (10/20 pts)")
    else:
        feedback_parts.append("FAIL: No emergency policy exceptions documented (0/20 pts)")

    # --- Criterion 5: Project with 'Recovery' or 'Ransomware' in title (15 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM projects WHERE (title LIKE \'%Recovery%\' OR title LIKE \'%recovery%\' OR title LIKE \'%Ransomware%\' OR title LIKE \'%ransomware%\') AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    cur_projects = _query_int(exec_in_env, 'SELECT COUNT(*) FROM projects WHERE deleted=0;')
    new_projects = max(0, cur_projects - b_projects)
    if result and result.strip():
        score += 15
        feedback_parts.append("PASS: Recovery/Ransomware remediation project found (15/15 pts)")
    elif new_projects >= 1:
        score += 7
        feedback_parts.append("PARTIAL: A project was created but title doesn't contain 'Recovery' or 'Ransomware' (7/15 pts)")
    else:
        feedback_parts.append("FAIL: No remediation project found (0/15 pts)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }
