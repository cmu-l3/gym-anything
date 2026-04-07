#!/usr/bin/env python3
import json
import tempfile
import os

def verify_deployment_rollout_deadlock(traj, env_info, task_info):
    """
    Verify that the agent diagnosed and remediated all 3 deployment rollouts.

    Scoring (100 pts total, pass threshold: 70):
    C1: ledger-writer uses 'Recreate' strategy (20 pts)
    C2: ledger-writer has v2 pods running (10 pts)
    C3: risk-analyzer uses maxSurge '0' or 'Recreate' strategy (20 pts)
    C4: risk-analyzer has 4 v2 pods running (15 pts)
    C5: compliance-api uses 'secret-reader' service account (20 pts)
    C6: compliance-api has v2 pods running (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {
            'passed': False,
            'score': 0,
            'feedback': 'copy_from_env not available in env_info'
        }

    result_path = '/tmp/deployment_rollout_deadlock_forensics_result.json'
    score = 0
    feedback_parts = []

    try:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name

        copy_from_env(result_path, tmp_path)

        with open(tmp_path, 'r') as f:
            result = json.load(f)

        os.unlink(tmp_path)

    except (FileNotFoundError, json.JSONDecodeError, Exception) as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Failed to read result file: {e}'
        }

    # ── Ledger Writer Checks ──────────────────────────────────────────────────
    ledger_strat = result.get('ledger_strategy', 'unknown')
    ledger_running = int(result.get('ledger_v2_running', 0))

    if ledger_strat == 'Recreate':
        score += 20
        feedback_parts.append('PASS C1: ledger-writer strategy corrected to Recreate (+20)')
    else:
        feedback_parts.append(f'FAIL C1: ledger-writer strategy is "{ledger_strat}" (expected "Recreate")')

    if ledger_running >= 1:
        score += 10
        feedback_parts.append(f'PASS C2: ledger-writer has {ledger_running} v2 pod(s) running (+10)')
    else:
        feedback_parts.append('FAIL C2: ledger-writer has NO v2 pods running (lock still held?)')

    # ── Risk Analyzer Checks ──────────────────────────────────────────────────
    risk_strat = result.get('risk_strategy', 'unknown')
    risk_surge = str(result.get('risk_max_surge', 'unknown'))
    risk_running = int(result.get('risk_v2_running', 0))

    if risk_surge in ['0', '0%'] or risk_strat == 'Recreate':
        score += 20
        feedback_parts.append('PASS C3: risk-analyzer rolling update surge constraints corrected to respect Quota (+20)')
    else:
        feedback_parts.append(f'FAIL C3: risk-analyzer maxSurge is "{risk_surge}" and strategy "{risk_strat}" (violates Quota)')

    if risk_running >= 4:
        score += 15
        feedback_parts.append('PASS C4: risk-analyzer has 4 v2 pods running (+15)')
    elif risk_running > 0:
        feedback_parts.append(f'FAIL C4: risk-analyzer has only {risk_running}/4 v2 pods running (partial rollout)')
    else:
        feedback_parts.append('FAIL C4: risk-analyzer has NO v2 pods running (blocked by Quota)')

    # ── Compliance API Checks ─────────────────────────────────────────────────
    comp_sa = result.get('compliance_sa', 'unknown')
    comp_running = int(result.get('compliance_v2_running', 0))

    if comp_sa == 'secret-reader':
        score += 20
        feedback_parts.append('PASS C5: compliance-api serviceAccountName corrected to secret-reader (+20)')
    else:
        feedback_parts.append(f'FAIL C5: compliance-api uses incorrect serviceAccountName "{comp_sa}"')

    if comp_running >= 1:
        score += 15
        feedback_parts.append(f'PASS C6: compliance-api has {comp_running} v2 pod(s) running (+15)')
    else:
        feedback_parts.append('FAIL C6: compliance-api has NO v2 pods running (crashing due to RBAC denial)')

    pass_threshold = task_info.get('metadata', {}).get('pass_threshold', 70)
    passed = score >= pass_threshold

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback_parts)
    }