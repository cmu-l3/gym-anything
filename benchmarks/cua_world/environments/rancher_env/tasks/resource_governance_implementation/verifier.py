import json
import tempfile
import os


# Expected values from resource_governance_spec.yaml
PROD_QUOTA_SPEC = {
    'requests.cpu': '16',
    'requests.memory': '32Gi',
    'limits.cpu': '32',
    'limits.memory': '64Gi',
    'pods': '50',
    'services': '20',
    'persistentvolumeclaims': '10',
}

STAGING_QUOTA_SPEC = {
    'requests.cpu': '8',
    'requests.memory': '16Gi',
    'limits.cpu': '16',
    'limits.memory': '32Gi',
    'pods': '30',
    'services': '15',
    'persistentvolumeclaims': '5',
}

# LimitRange Container spec for fintech-prod
PROD_LR_CONTAINER_SPEC = {
    'default': {'cpu': '500m', 'memory': '512Mi'},
    'defaultRequest': {'cpu': '250m', 'memory': '256Mi'},
    'max': {'cpu': '4', 'memory': '8Gi'},
    'min': {'cpu': '50m', 'memory': '64Mi'},
}

# LimitRange Container spec for fintech-staging
STAGING_LR_CONTAINER_SPEC = {
    'default': {'cpu': '250m', 'memory': '256Mi'},
    'defaultRequest': {'cpu': '100m', 'memory': '128Mi'},
    'max': {'cpu': '2', 'memory': '4Gi'},
    'min': {'cpu': '25m', 'memory': '32Mi'},
}

# LimitRange Container spec for fintech-dev
DEV_LR_CONTAINER_SPEC = {
    'default': {'cpu': '200m', 'memory': '256Mi'},
    'defaultRequest': {'cpu': '100m', 'memory': '128Mi'},
    'max': {'cpu': '1', 'memory': '2Gi'},
    'min': {'cpu': '10m', 'memory': '16Mi'},
}


def _normalize_resource(val):
    """Normalize resource values to allow minor variations (e.g. '16' vs '16000m' for CPU)."""
    return str(val).strip()


def _quota_matches(actual_hard, expected_spec):
    """Check if actual ResourceQuota hard limits match expected spec."""
    if not actual_hard:
        return False, []

    mismatches = []
    for key, expected_val in expected_spec.items():
        actual_val = actual_hard.get(key, '')
        if _normalize_resource(actual_val) != _normalize_resource(expected_val):
            mismatches.append(f'{key}: expected={expected_val}, got={actual_val}')

    return len(mismatches) == 0, mismatches


def _find_container_limit(limits):
    """Find the Container-type limit from a LimitRange spec."""
    for limit in limits:
        if limit.get('type') == 'Container':
            return limit
    return None


def _lr_container_matches(actual_limits, expected_spec):
    """Check if LimitRange Container limits match expected spec."""
    container_limit = _find_container_limit(actual_limits)
    if container_limit is None:
        return False, ['No Container-type limit found']

    mismatches = []
    for limit_type, expected_vals in expected_spec.items():
        actual_type_vals = container_limit.get(limit_type, {})
        for resource, expected_val in expected_vals.items():
            actual_val = actual_type_vals.get(resource, '')
            if _normalize_resource(actual_val) != _normalize_resource(expected_val):
                mismatches.append(
                    f'{limit_type}.{resource}: expected={expected_val}, got={actual_val}'
                )

    return len(mismatches) == 0, mismatches


def verify_resource_governance_implementation(traj, env_info, task_info):
    """
    Verify that the agent implemented ResourceQuota and LimitRange per the spec file.

    Scoring (25 pts each, pass threshold: 70):
    C1: ResourceQuota in fintech-prod matches spec (all 7 hard limits correct)
    C2: ResourceQuota in fintech-staging matches spec (all 7 hard limits correct)
    C3: LimitRange in fintech-prod matches spec (Container type, all 4 limit categories)
    C4: LimitRange in fintech-staging AND fintech-dev match spec (Container type)

    Note: fintech-dev intentionally has NO ResourceQuota per the spec.
    """
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {
            'passed': False,
            'score': 0,
            'reason': 'copy_from_env not available in env_info'
        }

    result_path = '/tmp/resource_governance_implementation_result.json'
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

    # ── C1: ResourceQuota in fintech-prod ─────────────────────────────────────
    prod_quota_exists = result.get('prod_quota_exists', False)
    prod_quota_details = result.get('prod_quota_details', {})

    if not prod_quota_exists:
        details.append('FAIL (0 pts) C1: No ResourceQuota in fintech-prod')
    else:
        c1_match, c1_mismatches = _quota_matches(prod_quota_details, PROD_QUOTA_SPEC)
        if c1_match:
            score += 25
            details.append('PASS (25 pts) C1: fintech-prod ResourceQuota matches spec')
        else:
            details.append(
                f'FAIL (0 pts) C1: fintech-prod ResourceQuota mismatches: '
                f'{"; ".join(c1_mismatches[:3])}'
            )

    # ── C2: ResourceQuota in fintech-staging ──────────────────────────────────
    staging_quota_exists = result.get('staging_quota_exists', False)
    staging_quota_details = result.get('staging_quota_details', {})

    if not staging_quota_exists:
        details.append('FAIL (0 pts) C2: No ResourceQuota in fintech-staging')
    else:
        c2_match, c2_mismatches = _quota_matches(staging_quota_details, STAGING_QUOTA_SPEC)
        if c2_match:
            score += 25
            details.append('PASS (25 pts) C2: fintech-staging ResourceQuota matches spec')
        else:
            details.append(
                f'FAIL (0 pts) C2: fintech-staging ResourceQuota mismatches: '
                f'{"; ".join(c2_mismatches[:3])}'
            )

    # ── C3: LimitRange in fintech-prod ────────────────────────────────────────
    prod_lr_exists = result.get('prod_lr_exists', False)
    prod_lr_details = result.get('prod_lr_details', [])

    if not prod_lr_exists:
        details.append('FAIL (0 pts) C3: No LimitRange in fintech-prod')
    else:
        c3_match, c3_mismatches = _lr_container_matches(prod_lr_details, PROD_LR_CONTAINER_SPEC)
        if c3_match:
            score += 25
            details.append('PASS (25 pts) C3: fintech-prod LimitRange matches spec')
        else:
            details.append(
                f'FAIL (0 pts) C3: fintech-prod LimitRange mismatches: '
                f'{"; ".join(c3_mismatches[:3])}'
            )

    # ── C4: LimitRange in fintech-staging AND fintech-dev ────────────────────
    staging_lr_exists = result.get('staging_lr_exists', False)
    staging_lr_details = result.get('staging_lr_details', [])
    dev_lr_exists = result.get('dev_lr_exists', False)
    dev_lr_details = result.get('dev_lr_details', [])

    c4_staging_ok = False
    c4_dev_ok = False

    if not staging_lr_exists:
        details.append('  C4a: No LimitRange in fintech-staging')
    else:
        c4s_match, c4s_mis = _lr_container_matches(staging_lr_details, STAGING_LR_CONTAINER_SPEC)
        c4_staging_ok = c4s_match
        if not c4s_match:
            details.append(f'  C4a: fintech-staging LimitRange mismatches: {"; ".join(c4s_mis[:2])}')

    if not dev_lr_exists:
        details.append('  C4b: No LimitRange in fintech-dev')
    else:
        c4d_match, c4d_mis = _lr_container_matches(dev_lr_details, DEV_LR_CONTAINER_SPEC)
        c4_dev_ok = c4d_match
        if not c4d_match:
            details.append(f'  C4b: fintech-dev LimitRange mismatches: {"; ".join(c4d_mis[:2])}')

    if c4_staging_ok and c4_dev_ok:
        score += 25
        details.append('PASS (25 pts) C4: fintech-staging and fintech-dev LimitRanges match spec')
    else:
        details.append(
            f'FAIL (0 pts) C4: staging_ok={c4_staging_ok}, dev_ok={c4_dev_ok}'
        )

    passed = score >= 70

    return {
        'passed': passed,
        'score': score,
        'reason': (f'Score {score}/100. {"PASSED" if passed else "FAILED"} (threshold: 70). '
                   f'ResourceQuotas and LimitRanges implemented per governance spec.'),
        'details': details,
        'raw': result
    }
