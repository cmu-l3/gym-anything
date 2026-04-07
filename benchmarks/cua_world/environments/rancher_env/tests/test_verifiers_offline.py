#!/usr/bin/env python3
"""
Offline unit tests for all 5 rancher_env task verifiers.

Run with:
    python3 examples/rancher_env/tests/test_verifiers_offline.py

No live VM or environment is required. Uses mocked copy_from_env to inject
synthetic result JSON.
"""

import importlib.util
import json
import os
import sys

# ── Helpers ──────────────────────────────────────────────────────────────────

TASKS_DIR = os.path.join(os.path.dirname(__file__), '..', 'tasks')


def load_verifier(task_name):
    path = os.path.join(TASKS_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location('verifier', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_env(result_data):
    """Create env_info with mocked copy_from_env that writes result_data."""
    def copy_from_env(src, dst):
        with open(dst, 'w', encoding='utf-8') as f:
            json.dump(result_data, f)
    return {'copy_from_env': copy_from_env}


def make_env_missing():
    """Simulate result file not existing (export script never ran)."""
    def copy_from_env(src, dst):
        raise FileNotFoundError(f'No such file: {src}')
    return {'copy_from_env': copy_from_env}


def run_test(label, result, condition, msg=''):
    if condition:
        print(f'  PASS: {label}')
    else:
        print(f'  FAIL: {label} — {msg}')
        print(f'        result={result}')
        sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# Task 1: production_incident_response
# ─────────────────────────────────────────────────────────────────────────────

def test_production_incident_response():
    print('\n=== production_incident_response ===')
    mod = load_verifier('production_incident_response')
    fn = mod.verify_production_incident_response
    task_info = {'metadata': {'pass_threshold': 70}}

    # 1a. File missing → score=0, passed=False
    r = fn([], make_env_missing(), task_info)
    run_test('missing file → score=0', r, r['passed'] is False and r['score'] == 0)

    # Structure from export_result.sh: nested dicts + namespace sentinel
    # 1b. Do-nothing (all failures still present)
    do_nothing = {
        'namespace': 'ecommerce',
        'api_gateway': {'pods_running': 0, 'current_image': 'nginx:broken-tag-xyz-nonexistent'},
        'web_frontend': {'endpoint_count': 0, 'has_endpoints': False},
        'cache_layer': {'redis_port': '6380', 'port_correct': False},
        'batch_processor': {'pods_running': 0, 'memory_request': '32Gi'},
        'total_pods_running': 0,
    }
    r = fn([], make_env(do_nothing), task_info)
    run_test('do-nothing → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('do-nothing → score=0', r, r['score'] == 0,
             f'score={r["score"]}')

    # 1c. Partial: fix 2 of 4 (api-gateway + web-frontend, not cache or batch)
    partial = {
        'namespace': 'ecommerce',
        'api_gateway': {'pods_running': 2, 'current_image': 'nginx:alpine'},
        'web_frontend': {'endpoint_count': 2, 'has_endpoints': True},
        'cache_layer': {'redis_port': '6380', 'port_correct': False},
        'batch_processor': {'pods_running': 0, 'memory_request': '32Gi'},
        'total_pods_running': 2,
    }
    r = fn([], make_env(partial), task_info)
    run_test('partial (2/4) → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('partial (2/4) → score=50', r, r['score'] == 50,
             f'score={r["score"]}')

    # 1d. Full completion: all 4 fixed
    full = {
        'namespace': 'ecommerce',
        'api_gateway': {'pods_running': 2, 'current_image': 'nginx:stable'},
        'web_frontend': {'endpoint_count': 3, 'has_endpoints': True},
        'cache_layer': {'redis_port': '6379', 'port_correct': True},
        'batch_processor': {'pods_running': 1, 'memory_request': '512Mi'},
        'total_pods_running': 6,
    }
    r = fn([], make_env(full), task_info)
    run_test('full (4/4) → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('full (4/4) → score=100', r, r['score'] == 100,
             f'score={r["score"]}')

    # 1e. 3/4 fixed should also pass (≥70)
    three_of_four = {
        'namespace': 'ecommerce',
        'api_gateway': {'pods_running': 2, 'current_image': 'nginx:stable'},
        'web_frontend': {'endpoint_count': 3, 'has_endpoints': True},
        'cache_layer': {'redis_port': '6379', 'port_correct': True},
        'batch_processor': {'pods_running': 0, 'memory_request': '32Gi'},
        'total_pods_running': 5,
    }
    r = fn([], make_env(three_of_four), task_info)
    run_test('3/4 fixed → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('3/4 fixed → score=75', r, r['score'] == 75,
             f'score={r["score"]}')

    # 1f. Wrong namespace → score=0
    wrong_ns = dict(full)
    wrong_ns['namespace'] = 'default'
    r = fn([], make_env(wrong_ns), task_info)
    run_test('wrong namespace → score=0', r, r['score'] == 0 and r['passed'] is False,
             f'score={r["score"]}')

    print('  ALL TESTS PASSED')


# ─────────────────────────────────────────────────────────────────────────────
# Task 2: rbac_least_privilege_audit
# ─────────────────────────────────────────────────────────────────────────────

def test_rbac_least_privilege_audit():
    print('\n=== rbac_least_privilege_audit ===')
    mod = load_verifier('rbac_least_privilege_audit')
    fn = mod.verify_rbac_least_privilege_audit
    task_info = {'metadata': {'pass_threshold': 70}}

    # 2a. File missing → score=0
    r = fn([], make_env_missing(), task_info)
    run_test('missing file → score=0', r, r['passed'] is False and r['score'] == 0)

    # 2b. Do-nothing (all violations still present)
    do_nothing = {
        'dev_crb_roleref': 'cluster-admin',
        'dev_crb_subject_kind': 'ServiceAccount',
        'dev_crb_subject_ns': 'development',
        'wildcard_role_exists': '1',
        'wildcard_role_verbs': '["*"]',
        'wildcard_role_resources': '["*"]',
        'wildcard_role_apigroups': '["*"]',
        'wildcard_rb_roleref': 'wildcard-staging-role',
        'mon_crb_roleref': 'cluster-admin',
        'mon_crb_subject_sa': 'metrics-collector',
        'mon_crb_subject_ns': 'monitoring',
        'ci_rb_roleref': 'cluster-admin',
        'ci_rb_subject_sa': 'ci-runner',
        'dev_replacement_crb': 'none',
        'dev_scoped_rb': 'none',
        'mon_scoped_rb': 'none',
    }
    r = fn([], make_env(do_nothing), task_info)
    run_test('do-nothing → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('do-nothing → score=0', r, r['score'] == 0,
             f'score={r["score"]}')

    # 2c. Fix C1 and C3 (delete the two cluster-admin CRBs)
    partial_c1_c3 = dict(do_nothing)
    partial_c1_c3['dev_crb_roleref'] = 'deleted'
    partial_c1_c3['mon_crb_roleref'] = 'deleted'
    r = fn([], make_env(partial_c1_c3), task_info)
    run_test('C1+C3 fixed → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('C1+C3 fixed → score=50', r, r['score'] == 50,
             f'score={r["score"]}')

    # 2d. Fix all 4
    all_fixed = dict(do_nothing)
    all_fixed['dev_crb_roleref'] = 'deleted'
    all_fixed['wildcard_role_exists'] = '0'
    all_fixed['wildcard_role_verbs'] = 'deleted'
    all_fixed['wildcard_role_resources'] = 'deleted'
    all_fixed['mon_crb_roleref'] = 'deleted'
    all_fixed['ci_rb_roleref'] = 'deleted'
    r = fn([], make_env(all_fixed), task_info)
    run_test('all fixed → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('all fixed → score=100', r, r['score'] == 100,
             f'score={r["score"]}')

    # 2e. Fix C1, C2, C4 (3 of 4) → should pass
    three_fixed = dict(do_nothing)
    three_fixed['dev_crb_roleref'] = 'deleted'
    three_fixed['wildcard_role_exists'] = '0'
    three_fixed['wildcard_role_verbs'] = 'deleted'
    three_fixed['wildcard_role_resources'] = 'deleted'
    three_fixed['ci_rb_roleref'] = 'deleted'
    r = fn([], make_env(three_fixed), task_info)
    run_test('C1+C2+C4 fixed → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('C1+C2+C4 fixed → score=75', r, r['score'] == 75,
             f'score={r["score"]}')

    print('  ALL TESTS PASSED')


# ─────────────────────────────────────────────────────────────────────────────
# Task 3: resource_governance_implementation
# ─────────────────────────────────────────────────────────────────────────────

def test_resource_governance_implementation():
    print('\n=== resource_governance_implementation ===')
    mod = load_verifier('resource_governance_implementation')
    fn = mod.verify_resource_governance_implementation
    task_info = {'metadata': {'pass_threshold': 70}}

    # 3a. File missing → score=0
    r = fn([], make_env_missing(), task_info)
    run_test('missing file → score=0', r, r['passed'] is False and r['score'] == 0)

    # 3b. Do-nothing (no quotas or limit ranges exist)
    do_nothing = {
        'prod_quota_exists': False,
        'prod_quota_details': {},
        'staging_quota_exists': False,
        'staging_quota_details': {},
        'prod_lr_exists': False,
        'prod_lr_details': [],
        'staging_lr_exists': False,
        'staging_lr_details': [],
        'dev_lr_exists': False,
        'dev_lr_details': [],
    }
    r = fn([], make_env(do_nothing), task_info)
    run_test('do-nothing → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('do-nothing → score=0', r, r['score'] == 0,
             f'score={r["score"]}')

    # 3c. Correct prod and staging quotas only (50 pts)
    prod_quota_correct = {
        'requests.cpu': '16', 'requests.memory': '32Gi',
        'limits.cpu': '32', 'limits.memory': '64Gi',
        'pods': '50', 'services': '20', 'persistentvolumeclaims': '10',
    }
    staging_quota_correct = {
        'requests.cpu': '8', 'requests.memory': '16Gi',
        'limits.cpu': '16', 'limits.memory': '32Gi',
        'pods': '30', 'services': '15', 'persistentvolumeclaims': '5',
    }
    partial = dict(do_nothing)
    partial['prod_quota_exists'] = True
    partial['prod_quota_details'] = prod_quota_correct
    partial['staging_quota_exists'] = True
    partial['staging_quota_details'] = staging_quota_correct
    r = fn([], make_env(partial), task_info)
    run_test('C1+C2 correct → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('C1+C2 correct → score=50', r, r['score'] == 50,
             f'score={r["score"]}')

    # 3d. Full completion
    prod_lr_correct = [
        {
            'type': 'Container',
            'default': {'cpu': '500m', 'memory': '512Mi'},
            'defaultRequest': {'cpu': '250m', 'memory': '256Mi'},
            'max': {'cpu': '4', 'memory': '8Gi'},
            'min': {'cpu': '50m', 'memory': '64Mi'},
        }
    ]
    staging_lr_correct = [
        {
            'type': 'Container',
            'default': {'cpu': '250m', 'memory': '256Mi'},
            'defaultRequest': {'cpu': '100m', 'memory': '128Mi'},
            'max': {'cpu': '2', 'memory': '4Gi'},
            'min': {'cpu': '25m', 'memory': '32Mi'},
        }
    ]
    dev_lr_correct = [
        {
            'type': 'Container',
            'default': {'cpu': '200m', 'memory': '256Mi'},
            'defaultRequest': {'cpu': '100m', 'memory': '128Mi'},
            'max': {'cpu': '1', 'memory': '2Gi'},
            'min': {'cpu': '10m', 'memory': '16Mi'},
        }
    ]
    full = {
        'prod_quota_exists': True,
        'prod_quota_details': prod_quota_correct,
        'staging_quota_exists': True,
        'staging_quota_details': staging_quota_correct,
        'prod_lr_exists': True,
        'prod_lr_details': prod_lr_correct,
        'staging_lr_exists': True,
        'staging_lr_details': staging_lr_correct,
        'dev_lr_exists': True,
        'dev_lr_details': dev_lr_correct,
    }
    r = fn([], make_env(full), task_info)
    run_test('full → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('full → score=100', r, r['score'] == 100,
             f'score={r["score"]}')

    # 3e. Wrong quota values → no points for C1
    wrong_prod_quota = dict(prod_quota_correct)
    wrong_prod_quota['requests.cpu'] = '8'   # wrong — spec says 16
    partial_wrong = dict(full)
    partial_wrong['prod_quota_details'] = wrong_prod_quota
    r = fn([], make_env(partial_wrong), task_info)
    run_test('wrong prod quota → C1 fails', r, r['score'] <= 75,
             f'score={r["score"]}')

    print('  ALL TESTS PASSED')


# ─────────────────────────────────────────────────────────────────────────────
# Task 4: network_policy_zero_trust
# ─────────────────────────────────────────────────────────────────────────────

def test_network_policy_zero_trust():
    print('\n=== network_policy_zero_trust ===')
    mod = load_verifier('network_policy_zero_trust')
    fn = mod.verify_network_policy_zero_trust
    task_info = {'metadata': {'pass_threshold': 70}}

    # 4a. File missing → score=0
    r = fn([], make_env_missing(), task_info)
    run_test('missing file → score=0', r, r['passed'] is False and r['score'] == 0)

    # 4b. Do-nothing (no network policies)
    do_nothing = {
        'total_policies': 0,
        'policy_names': [],
        'c1_exists': False,
        'c1_pod_selector_empty': False,
        'c1_has_ingress_type': False,
        'c1_has_egress_type': False,
        'c1_ingress_empty': False,
        'c1_egress_empty': False,
        'c2_exists': False,
        'c2_ingress_from_ingress_ns': False,
        'c2_egress_to_api_gateway': False,
        'c3_exists': False,
        'c3_ingress_from_frontend': False,
        'c3_egress_to_auth': False,
        'c3_egress_to_account': False,
        'c4_exists': False,
        'c4_ingress_from_account_service_only': False,
        'c4_ingress_sources_count': 0,
        'c4_port_5432': False,
    }
    r = fn([], make_env(do_nothing), task_info)
    run_test('do-nothing → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('do-nothing → score=0', r, r['score'] == 0,
             f'score={r["score"]}')

    # 4c. Only C1 (default-deny) created
    c1_only = dict(do_nothing)
    c1_only['c1_exists'] = True
    c1_only['c1_pod_selector_empty'] = True
    c1_only['c1_has_ingress_type'] = True
    c1_only['c1_has_egress_type'] = True
    c1_only['c1_ingress_empty'] = True
    c1_only['c1_egress_empty'] = True
    c1_only['total_policies'] = 1
    c1_only['policy_names'] = ['default-deny-all']
    r = fn([], make_env(c1_only), task_info)
    run_test('C1 only → score=25', r, r['score'] == 25,
             f'score={r["score"]}')
    run_test('C1 only → passed=False', r, r['passed'] is False)

    # 4d. Full completion
    full = {
        'total_policies': 6,
        'policy_names': ['default-deny-all', 'allow-frontend-ingress', 'allow-api-gateway',
                         'allow-auth-service', 'allow-account-service', 'allow-account-db-ingress'],
        'c1_exists': True,
        'c1_pod_selector_empty': True,
        'c1_has_ingress_type': True,
        'c1_has_egress_type': True,
        'c1_ingress_empty': True,
        'c1_egress_empty': True,
        'c2_exists': True,
        'c2_ingress_from_ingress_ns': True,
        'c2_egress_to_api_gateway': True,
        'c3_exists': True,
        'c3_ingress_from_frontend': True,
        'c3_egress_to_auth': True,
        'c3_egress_to_account': True,
        'c4_exists': True,
        'c4_ingress_from_account_service_only': True,
        'c4_ingress_sources_count': 1,
        'c4_port_5432': True,
    }
    r = fn([], make_env(full), task_info)
    run_test('full → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('full → score=100', r, r['score'] == 100,
             f'score={r["score"]}')

    # 4e. C4 without port 5432 → C4 fails
    no_port = dict(full)
    no_port['c4_port_5432'] = False
    r = fn([], make_env(no_port), task_info)
    run_test('C4 no port 5432 → score=75', r, r['score'] == 75,
             f'score={r["score"]}')

    # 4f. 3 of 4 correct → passes
    three_of_four = dict(full)
    three_of_four['c2_exists'] = False
    three_of_four['c2_ingress_from_ingress_ns'] = False
    three_of_four['c2_egress_to_api_gateway'] = False
    r = fn([], make_env(three_of_four), task_info)
    run_test('3/4 → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('3/4 → score=75', r, r['score'] == 75,
             f'score={r["score"]}')

    print('  ALL TESTS PASSED')


# ─────────────────────────────────────────────────────────────────────────────
# Task 5: statefulset_database_recovery
# ─────────────────────────────────────────────────────────────────────────────

def test_statefulset_database_recovery():
    print('\n=== statefulset_database_recovery ===')
    mod = load_verifier('statefulset_database_recovery')
    fn = mod.verify_statefulset_database_recovery
    task_info = {'metadata': {'pass_threshold': 70}}

    # 5a. File missing → score=0
    r = fn([], make_env_missing(), task_info)
    run_test('missing file → score=0', r, r['passed'] is False and r['score'] == 0)

    # 5b. Do-nothing (all 4 failures present, pods=0)
    do_nothing = {
        'pods_running': 0,
        'pods_total': 0,
        'pods_phases': '',
        'pvc_has_premium_ssd': True,
        'postgres_pvc_storageclass': 'premium-ssd',
        'pvc_storageclass_details': [{'name': 'postgres-data-postgres-primary-0',
                                       'storageClass': 'premium-ssd'}],
        'secret_refs': ['postgres-db-secret'],
        'correct_secret_exists': True,
        'wrong_secret_still_referenced': True,
        'correct_secret_referenced': False,
        'memory_request': '32Gi',
        'memory_request_gi': 32.0,
        'volume_mount_path': '/var/lib/psql',
    }
    r = fn([], make_env(do_nothing), task_info)
    run_test('do-nothing → passed=False', r, r['passed'] is False,
             f'score={r["score"]}')
    run_test('do-nothing → score=0', r, r['score'] == 0,
             f'score={r["score"]}')

    # 5c. Fix C2 (StorageClass) + C3 (Secret) + C4 (Memory) but pods still not running
    # Volume mount path failure still prevents pods from starting, but 3/4 criteria
    # are directly verified and score 75, which passes (>= 70 threshold).
    three_fixed_no_pods = dict(do_nothing)
    three_fixed_no_pods['pvc_has_premium_ssd'] = False
    three_fixed_no_pods['postgres_pvc_storageclass'] = 'local-path'
    three_fixed_no_pods['wrong_secret_still_referenced'] = False
    three_fixed_no_pods['correct_secret_referenced'] = True
    three_fixed_no_pods['secret_refs'] = ['postgres-credentials']
    three_fixed_no_pods['memory_request'] = '512Mi'
    three_fixed_no_pods['memory_request_gi'] = 0.5
    r = fn([], make_env(three_fixed_no_pods), task_info)
    run_test('C2+C3+C4 fixed, no pods → passed=True (3/4 = 75 pts >= 70)', r,
             r['passed'] is True, f'score={r["score"]}')
    run_test('C2+C3+C4 fixed, no pods → score=75', r, r['score'] == 75,
             f'score={r["score"]}')

    # 5d. Full completion (all 4 failures fixed, pods running)
    full = {
        'pods_running': 1,
        'pods_total': 1,
        'pods_phases': 'Running',
        'pvc_has_premium_ssd': False,
        'postgres_pvc_storageclass': 'local-path',
        'pvc_storageclass_details': [{'name': 'postgres-data-postgres-primary-0',
                                       'storageClass': 'local-path'}],
        'secret_refs': ['postgres-credentials'],
        'correct_secret_exists': True,
        'wrong_secret_still_referenced': False,
        'correct_secret_referenced': True,
        'memory_request': '512Mi',
        'memory_request_gi': 0.5,
        'volume_mount_path': '/var/lib/postgresql/data',
    }
    r = fn([], make_env(full), task_info)
    run_test('full → passed=True', r, r['passed'] is True,
             f'score={r["score"]}')
    run_test('full → score=100', r, r['score'] == 100,
             f'score={r["score"]}')

    # 5e. Memory still too high (> 4Gi) even though other things fixed
    high_memory = dict(full)
    high_memory['memory_request'] = '8Gi'
    high_memory['memory_request_gi'] = 8.0
    r = fn([], make_env(high_memory), task_info)
    run_test('high memory → C4 fails', r, r['score'] <= 75,
             f'score={r["score"]}')

    print('  ALL TESTS PASSED')


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    print('Running offline verifier unit tests for all 5 rancher_env tasks...')

    test_production_incident_response()
    test_rbac_least_privilege_audit()
    test_resource_governance_implementation()
    test_network_policy_zero_trust()
    test_statefulset_database_recovery()

    print('\n' + '=' * 60)
    print('ALL OFFLINE VERIFIER TESTS PASSED')
    print('=' * 60)
