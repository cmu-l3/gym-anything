#!/usr/bin/env python3
"""Verifier for pci_dss_gap_remediation task.

Scoring (100 pts total, pass >= 60):
  - 6 new risks with Mitigate treatment:         39 pts (6.5 each, up to 6)
  - >=3 new internal controls:                   21 pts
  - Project with 'PCI' in title:                 10 pts
  - >=2 new policy exceptions:                   15 pts
  - 'Payment Card Data Security Policy' (Draft): 15 pts

Baseline counts read from /tmp/pci_dss_gap_remediation_baseline.txt.
risk_mitigation_strategies: 1=Accept, 2=Avoid, 3=Mitigate, 4=Transfer
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


def verify_pci_dss_gap_remediation(traj, env_info, task_info):
    exec_in_env = env_info.get('exec_in_env') or env_info.get('exec_capture')
    if not exec_in_env:
        return {"passed": False, "score": 0, "feedback": "exec_capture not available"}

    # Load baseline
    raw = exec_in_env('cat /tmp/pci_dss_gap_remediation_baseline.txt 2>/dev/null') or ''
    baseline = _parse_baseline(raw)
    b_mitigate = baseline.get('BASELINE_MITIGATE_RISKS', 1)
    b_services = baseline.get('BASELINE_SERVICES', 2)
    b_exceptions = baseline.get('BASELINE_EXCEPTIONS', 0)
    b_projects = baseline.get('BASELINE_PROJECTS', 0)
    b_policies = baseline.get('BASELINE_POLICIES', 2)

    score = 0
    feedback_parts = []

    # --- Criterion 1: 6 new risks with Mitigate treatment (39 pts, 6.5 each) ---
    cur_mitigate = _query_int(
        exec_in_env,
        'SELECT COUNT(*) FROM risks WHERE risk_mitigation_strategy_id=3 AND deleted=0;'
    )
    new_mitigate = max(0, cur_mitigate - b_mitigate)
    pts = min(6, new_mitigate) * 6  # 6 pts per risk (floor), cap at 6
    # Award 39 if all 6 present, otherwise partial
    if new_mitigate >= 6:
        pts = 39
    elif new_mitigate >= 5:
        pts = 32
    elif new_mitigate >= 4:
        pts = 26
    elif new_mitigate >= 3:
        pts = 19
    elif new_mitigate >= 2:
        pts = 13
    elif new_mitigate >= 1:
        pts = 6
    else:
        pts = 0
    score += pts
    if new_mitigate >= 6:
        feedback_parts.append(f"PASS: {new_mitigate} new risks with Mitigate treatment ({pts}/39 pts)")
    else:
        feedback_parts.append(f"PARTIAL: {new_mitigate}/6 new risks with Mitigate treatment ({pts}/39 pts)")

    # --- Criterion 2: >=3 new internal controls (21 pts) ---
    cur_services = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_services WHERE deleted=0;')
    new_services = max(0, cur_services - b_services)
    if new_services >= 3:
        score += 21
        feedback_parts.append(f"PASS: {new_services} new internal controls (21/21 pts)")
    elif new_services == 2:
        score += 14
        feedback_parts.append(f"PARTIAL: {new_services}/3 new internal controls (14/21 pts)")
    elif new_services == 1:
        score += 7
        feedback_parts.append(f"PARTIAL: {new_services}/3 new internal controls (7/21 pts)")
    else:
        feedback_parts.append("FAIL: No new internal controls found (0/21 pts)")

    # --- Criterion 3: Project with 'PCI' in title (10 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM projects WHERE (title LIKE \'%PCI%\' OR title LIKE \'%pci%\') AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    cur_projects = _query_int(exec_in_env, 'SELECT COUNT(*) FROM projects WHERE deleted=0;')
    new_projects = max(0, cur_projects - b_projects)
    if result and result.strip():
        score += 10
        feedback_parts.append("PASS: PCI project found (10/10 pts)")
    elif new_projects >= 1:
        score += 5
        feedback_parts.append("PARTIAL: Project created but title does not contain 'PCI' (5/10 pts)")
    else:
        feedback_parts.append("FAIL: No PCI remediation project found (0/10 pts)")

    # --- Criterion 4: >=2 new policy exceptions (15 pts) ---
    cur_exceptions = _query_int(exec_in_env, 'SELECT COUNT(*) FROM policy_exceptions;')
    new_exceptions = max(0, cur_exceptions - b_exceptions)
    if new_exceptions >= 2:
        score += 15
        feedback_parts.append(f"PASS: {new_exceptions} policy exceptions documented (15/15 pts)")
    elif new_exceptions == 1:
        score += 7
        feedback_parts.append("PARTIAL: 1/2 policy exceptions documented (7/15 pts)")
    else:
        feedback_parts.append("FAIL: No new policy exceptions found (0/15 pts)")

    # --- Criterion 5: Payment Card Data Security Policy (Draft) (15 pts) ---
    result = exec_in_env(
        'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
        '"SELECT id FROM security_policies WHERE ('
        '\\`index\\` LIKE \'%Payment Card%\' OR \\`index\\` LIKE \'%PCI%\' OR \\`index\\` LIKE \'%Cardholder%\''
        ') AND deleted=0 LIMIT 1;" 2>/dev/null'
    )
    cur_policies = _query_int(exec_in_env, 'SELECT COUNT(*) FROM security_policies WHERE deleted=0;')
    new_policies = max(0, cur_policies - b_policies)
    if result and result.strip():
        score += 15
        feedback_parts.append("PASS: Payment Card Data Security Policy found (15/15 pts)")
    elif new_policies >= 1:
        score += 5
        feedback_parts.append("PARTIAL: A new policy was created but title doesn't match 'Payment Card Data Security Policy' (5/15 pts)")
    else:
        feedback_parts.append("FAIL: Payment Card Data Security Policy not found (0/15 pts)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }
