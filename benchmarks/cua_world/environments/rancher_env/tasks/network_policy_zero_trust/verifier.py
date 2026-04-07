import json
import tempfile
import os


def verify_network_policy_zero_trust(traj, env_info, task_info):
    """
    Verify that the agent implemented zero-trust NetworkPolicies per the spec.

    Scoring (25 pts each, pass threshold: 70):

    C1 (25 pts): Default deny-all NetworkPolicy exists
        - podSelector: {} (empty — selects all pods)
        - policyTypes: [Ingress, Egress]
        - No ingress or egress rules (deny everything)

    C2 (25 pts): frontend-app policy exists with correct ingress/egress
        - Ingress allows from ingress-nginx namespace
        - Egress allows to api-gateway

    C3 (25 pts): api-gateway policy exists with correct ingress/egress
        - Ingress from frontend-app
        - Egress to auth-service AND account-service

    C4 (25 pts): account-db policy allows ingress ONLY from account-service on port 5432
        - No other ingress source allowed
        - Port 5432 explicitly specified
    """
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {
            'passed': False,
            'score': 0,
            'reason': 'copy_from_env not available in env_info'
        }

    result_path = '/tmp/network_policy_zero_trust_result.json'
    score = 0
    details = []

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
            'reason': f'Failed to read result file: {e}',
            'details': []
        }

    # ── C1: Default deny-all policy ───────────────────────────────────────────
    c1_exists = result.get('c1_exists', False)
    c1_pod_selector_empty = result.get('c1_pod_selector_empty', False)
    c1_has_ingress_type = result.get('c1_has_ingress_type', False)
    c1_has_egress_type = result.get('c1_has_egress_type', False)
    c1_ingress_empty = result.get('c1_ingress_empty', False)
    c1_egress_empty = result.get('c1_egress_empty', False)

    # Accept if: exists, selects all pods (empty selector), has both policy types,
    # and has no allow rules (i.e., it's a pure deny)
    c1_pass = (
        c1_exists and
        c1_has_ingress_type and
        c1_has_egress_type and
        c1_ingress_empty and
        c1_egress_empty
    )

    if c1_pass:
        score += 25
        details.append('PASS (25 pts) C1: default-deny-all NetworkPolicy correctly configured')
    else:
        if not c1_exists:
            details.append('FAIL (0 pts) C1: default-deny-all NetworkPolicy not found')
        else:
            reasons = []
            if not c1_has_ingress_type:
                reasons.append('missing Ingress policyType')
            if not c1_has_egress_type:
                reasons.append('missing Egress policyType')
            if not c1_ingress_empty:
                reasons.append('has ingress allow rules (should be empty for deny-all)')
            if not c1_egress_empty:
                reasons.append('has egress allow rules (should be empty for deny-all)')
            details.append(f'FAIL (0 pts) C1: default-deny-all incomplete: {"; ".join(reasons)}')

    # ── C2: Frontend policy ───────────────────────────────────────────────────
    c2_exists = result.get('c2_exists', False)
    c2_ingress_from_ingress_ns = result.get('c2_ingress_from_ingress_ns', False)
    c2_egress_to_api_gateway = result.get('c2_egress_to_api_gateway', False)

    c2_pass = c2_exists and c2_ingress_from_ingress_ns and c2_egress_to_api_gateway

    if c2_pass:
        score += 25
        details.append('PASS (25 pts) C2: frontend-app NetworkPolicy correctly configured')
    else:
        if not c2_exists:
            details.append('FAIL (0 pts) C2: No NetworkPolicy found for frontend-app')
        else:
            reasons = []
            if not c2_ingress_from_ingress_ns:
                reasons.append('ingress not restricted to ingress-nginx namespace')
            if not c2_egress_to_api_gateway:
                reasons.append('egress to api-gateway not specified')
            details.append(f'FAIL (0 pts) C2: frontend-app policy incomplete: {"; ".join(reasons)}')

    # ── C3: API gateway policy ────────────────────────────────────────────────
    c3_exists = result.get('c3_exists', False)
    c3_ingress_from_frontend = result.get('c3_ingress_from_frontend', False)
    c3_egress_to_auth = result.get('c3_egress_to_auth', False)
    c3_egress_to_account = result.get('c3_egress_to_account', False)

    c3_pass = c3_exists and c3_ingress_from_frontend and c3_egress_to_auth and c3_egress_to_account

    if c3_pass:
        score += 25
        details.append('PASS (25 pts) C3: api-gateway NetworkPolicy correctly configured')
    else:
        if not c3_exists:
            details.append('FAIL (0 pts) C3: No NetworkPolicy found for api-gateway')
        else:
            reasons = []
            if not c3_ingress_from_frontend:
                reasons.append('ingress from frontend-app not specified')
            if not c3_egress_to_auth:
                reasons.append('egress to auth-service not specified')
            if not c3_egress_to_account:
                reasons.append('egress to account-service not specified')
            details.append(f'FAIL (0 pts) C3: api-gateway policy incomplete: {"; ".join(reasons)}')

    # ── C4: Database policy ───────────────────────────────────────────────────
    c4_exists = result.get('c4_exists', False)
    c4_ingress_from_account_service_only = result.get('c4_ingress_from_account_service_only', False)
    c4_port_5432 = result.get('c4_port_5432', False)

    c4_pass = c4_exists and c4_ingress_from_account_service_only and c4_port_5432

    if c4_pass:
        score += 25
        details.append('PASS (25 pts) C4: account-db NetworkPolicy correctly restricts to account-service:5432')
    else:
        if not c4_exists:
            details.append('FAIL (0 pts) C4: No NetworkPolicy found for account-db')
        else:
            reasons = []
            if not c4_ingress_from_account_service_only:
                reasons.append('ingress not restricted to account-service pod selector')
            if not c4_port_5432:
                reasons.append('port 5432 not explicitly specified')
            details.append(f'FAIL (0 pts) C4: account-db policy incomplete: {"; ".join(reasons)}')

    passed = score >= 70

    return {
        'passed': passed,
        'score': score,
        'reason': (f'Score {score}/100. {"PASSED" if passed else "FAILED"} (threshold: 70). '
                   f'{sum([c1_pass, c2_pass, c3_pass, c4_pass])}/4 policies correctly implemented.'),
        'details': details,
        'raw': result
    }
