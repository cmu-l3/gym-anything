import json
import tempfile
import os


def verify_rbac_least_privilege_audit(traj, env_info, task_info):
    """
    Verify that the agent has remediated all 4 RBAC least-privilege violations:

    Violation 1 (25 pts): dev-automation ServiceAccount no longer has cluster-admin
        via the 'dev-all-access' ClusterRoleBinding. The binding must be deleted OR
        changed to a non-cluster-admin role.

    Violation 2 (25 pts): The wildcard-staging-role Role in 'staging' namespace no
        longer uses wildcard (*) for verbs, resources, and apiGroups. The role must
        be deleted OR restricted to specific permissions (no wildcards on all three).

    Violation 3 (25 pts): metrics-collector ServiceAccount no longer has cluster-admin
        via the 'monitoring-cluster-admin' ClusterRoleBinding. The binding must be
        deleted OR changed to a non-cluster-admin role.

    Violation 4 (25 pts): ci-runner ServiceAccount no longer has cluster-admin via
        the 'ci-elevated-access' RoleBinding in 'staging'. The binding must be deleted
        OR changed to a non-cluster-admin role.

    Pass threshold: 70 (3 out of 4 violations remediated)
    """
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {
            'passed': False,
            'score': 0,
            'reason': 'copy_from_env not available in env_info'
        }

    result_path = '/tmp/rbac_least_privilege_audit_result.json'
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

    # ── Criterion 1: dev-all-access no longer grants cluster-admin ────────────
    # Violation is fixed if:
    #   (a) dev-all-access is deleted (roleRef == "deleted"), OR
    #   (b) dev-all-access roleRef is not "cluster-admin"
    dev_crb_roleref = result.get('dev_crb_roleref', 'cluster-admin')
    c1_fixed = (dev_crb_roleref == 'deleted') or (
        dev_crb_roleref not in ('cluster-admin', '') and
        dev_crb_roleref != 'cluster-admin'
    )
    # Simpler: fixed if deleted or changed away from cluster-admin
    c1_fixed = (dev_crb_roleref == 'deleted') or (
        dev_crb_roleref not in ('cluster-admin',) and dev_crb_roleref != ''
    )

    if c1_fixed:
        score += 25
        details.append('PASS (25 pts): dev-all-access ClusterRoleBinding remediated '
                       f'(roleRef now: {dev_crb_roleref})')
    else:
        details.append(f'FAIL (0 pts): dev-all-access still grants cluster-admin '
                       f'(roleRef: {dev_crb_roleref})')

    # ── Criterion 2: wildcard-staging-role no longer uses full wildcards ───────
    # Violation is fixed if:
    #   (a) Role is deleted (wildcard_role_exists == "0"), OR
    #   (b) Rule does not use "*" for ALL THREE of verbs, resources, apiGroups
    wildcard_role_exists = result.get('wildcard_role_exists', '1')
    wildcard_verbs = result.get('wildcard_role_verbs', '["*"]')
    wildcard_resources = result.get('wildcard_role_resources', '["*"]')
    wildcard_apigroups = result.get('wildcard_role_apigroups', '["*"]')

    role_deleted = (wildcard_role_exists == '0' or
                    wildcard_verbs == 'deleted' or
                    wildcard_resources == 'deleted')

    # Check if still full-wildcard on all three dimensions
    still_wildcard = (
        '"*"' in wildcard_verbs and
        '"*"' in wildcard_resources and
        '"*"' in wildcard_apigroups
    )

    c2_fixed = role_deleted or not still_wildcard

    if c2_fixed:
        score += 25
        if role_deleted:
            details.append('PASS (25 pts): wildcard-staging-role deleted')
        else:
            details.append('PASS (25 pts): wildcard-staging-role restricted '
                           f'(verbs={wildcard_verbs}, resources={wildcard_resources})')
    else:
        details.append(f'FAIL (0 pts): wildcard-staging-role still uses * on all '
                       f'verbs/resources/apiGroups (verbs={wildcard_verbs})')

    # ── Criterion 3: monitoring-cluster-admin no longer grants cluster-admin ───
    # Violation is fixed if:
    #   (a) monitoring-cluster-admin is deleted (roleRef == "deleted"), OR
    #   (b) monitoring-cluster-admin roleRef is not "cluster-admin"
    mon_crb_roleref = result.get('mon_crb_roleref', 'cluster-admin')
    c3_fixed = (mon_crb_roleref == 'deleted') or (
        mon_crb_roleref not in ('cluster-admin',) and mon_crb_roleref != ''
    )

    if c3_fixed:
        score += 25
        details.append('PASS (25 pts): monitoring-cluster-admin ClusterRoleBinding '
                       f'remediated (roleRef now: {mon_crb_roleref})')
    else:
        details.append(f'FAIL (0 pts): monitoring-cluster-admin still grants '
                       f'cluster-admin (roleRef: {mon_crb_roleref})')

    # ── Criterion 4: ci-elevated-access no longer grants cluster-admin ─────────
    # Violation is fixed if:
    #   (a) ci-elevated-access is deleted (roleRef == "deleted"), OR
    #   (b) ci-elevated-access roleRef is not "cluster-admin"
    ci_rb_roleref = result.get('ci_rb_roleref', 'cluster-admin')
    c4_fixed = (ci_rb_roleref == 'deleted') or (
        ci_rb_roleref not in ('cluster-admin',) and ci_rb_roleref != ''
    )

    if c4_fixed:
        score += 25
        details.append('PASS (25 pts): ci-elevated-access RoleBinding remediated '
                       f'(roleRef now: {ci_rb_roleref})')
    else:
        details.append(f'FAIL (0 pts): ci-elevated-access still grants cluster-admin '
                       f'(roleRef: {ci_rb_roleref})')

    passed = score >= 70

    return {
        'passed': passed,
        'score': score,
        'reason': f'Score {score}/100. {"PASSED" if passed else "FAILED"} '
                  f'(threshold: 70). {sum([c1_fixed, c2_fixed, c3_fixed, c4_fixed])}/4 '
                  f'violations remediated.',
        'details': details,
        'raw': result
    }
