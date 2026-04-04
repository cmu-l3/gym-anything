#!/usr/bin/env python3
"""
Offline Phase 5 validation for all 5 new manageservice_env verifiers.
Tests: do-nothing (must score=0), partial completion, and partial-pass scenarios.
No VM required — uses mock copy_from_env that writes JSON from memory.
"""

import json
import os
import sys
import tempfile

# Add the tasks directory to the path so we can import verifiers
TASKS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TASKS_DIR)

from sla_compliance_problem_management.verifier import verify_sla_compliance_problem_management
from technician_group_routing_configuration.verifier import verify_technician_group_routing_configuration
from change_request_full_lifecycle.verifier import verify_change_request_full_lifecycle
from service_catalog_department_setup.verifier import verify_service_catalog_department_setup
from incident_resolution_knowledge_base.verifier import verify_incident_resolution_knowledge_base


def make_copy_from_env(data_dict):
    """Return a copy_from_env mock that ignores src and writes data_dict as JSON to dst."""
    def copy_fn(src, dst):
        with open(dst, 'w') as f:
            json.dump(data_dict, f)
    return copy_fn


def make_env_info(data_dict):
    return {'copy_from_env': make_copy_from_env(data_dict)}


def assert_score(label, result, expected_score=None, expected_passed=None, min_score=None, max_score=None):
    score = result['score']
    passed = result['passed']
    ok = True
    if expected_score is not None and score != expected_score:
        print(f"  FAIL [{label}]: expected score={expected_score}, got score={score}")
        ok = False
    if min_score is not None and score < min_score:
        print(f"  FAIL [{label}]: expected score>={min_score}, got score={score}")
        ok = False
    if max_score is not None and score > max_score:
        print(f"  FAIL [{label}]: expected score<={max_score}, got score={score}")
        ok = False
    if expected_passed is not None and passed != expected_passed:
        print(f"  FAIL [{label}]: expected passed={expected_passed}, got passed={passed}")
        ok = False
    if ok:
        print(f"  PASS [{label}]: score={score}, passed={passed}")
    else:
        print(f"       feedback: {result.get('feedback', '')[:200]}")
    return ok


def run_all():
    all_ok = True
    print("=" * 70)

    # ===== TASK 1: sla_compliance_problem_management =====
    print("\n[Task 1] sla_compliance_problem_management")

    # Do-nothing: all statuses=2 (Open), no problem
    r = verify_sla_compliance_problem_management(
        [], make_env_info({
            'status_1001': 2, 'status_1003': 2, 'status_1004': 2,
            'owner_1001': 0, 'owner_1003': 0, 'owner_1004': 0,
            'problem_found': False,
            'problem_title': '', 'problem_id': '',
            'problem_priority': '',
            'problem_linked_request_ids': [],
            'problem_linked_target_count': 0,
        }), {}
    )
    all_ok &= assert_score("do-nothing", r, expected_score=0, expected_passed=False)

    # Partial: 1 ticket changed, no problem
    r = verify_sla_compliance_problem_management(
        [], make_env_info({
            'status_1001': 3, 'status_1003': 2, 'status_1004': 2,  # 1001 changed to "In Progress"
            'status_name_1001': 'In Progress', 'status_name_1003': 'Open', 'status_name_1004': 'Open',
            'owner_1001': 5, 'owner_1003': 0, 'owner_1004': 0,
            'technician_name_1001': 'administrator', 'technician_name_1003': '', 'technician_name_1004': '',
            'problem_found': False,
            'problem_title': '', 'problem_id': '',
            'problem_priority': '',
            'problem_linked_request_ids': [],
            'problem_linked_target_count': 0,
        }), {}
    )
    # 1 ticket changed (10pts) + 1 assigned (8pts) = 18 pts, not passing
    all_ok &= assert_score("partial-1ticket", r, expected_passed=False, min_score=10, max_score=30)

    # Full pass: all 3 tickets changed + assigned + problem created + 2 tickets linked
    r = verify_sla_compliance_problem_management(
        [], make_env_info({
            'status_1001': 3, 'status_1003': 3, 'status_1004': 3,
            'status_name_1001': 'In Progress', 'status_name_1003': 'In Progress', 'status_name_1004': 'In Progress',
            'owner_1001': 5, 'owner_1003': 5, 'owner_1004': 5,
            'technician_name_1001': 'administrator', 'technician_name_1003': 'administrator', 'technician_name_1004': 'administrator',
            'problem_found': True,
            'problem_title': 'Recurring SLA Compliance Failures - High Priority Response Times',
            'problem_id': '42',
            'problem_priority': 'High',
            'problem_linked_request_ids': ['1001', '1003', '1004'],
            'problem_linked_target_count': 3,
        }), {}
    )
    # 30 + 25 + 25 + 20 = 100 pts
    all_ok &= assert_score("full-pass", r, expected_score=100, expected_passed=True)

    # ===== TASK 2: technician_group_routing_configuration =====
    print("\n[Task 2] technician_group_routing_configuration")

    # Do-nothing: no groups found
    r = verify_technician_group_routing_configuration(
        [], make_env_info({
            'network_group_found': False,
            'hardware_group_found': False,
            'maya_patel_found': False,
            'carlos_rivera_found': False,
            'ticket_1004_network_group': False,
            'ticket_1001_hardware_group': False,
            'ticket_1004_group_name': '',
            'ticket_1001_group_name': '',
            'maya_count_sql': 0, 'maya_patel_found_api': False,
            'carlos_count_sql': 0, 'carlos_rivera_found_api': False,
        }), {}
    )
    all_ok &= assert_score("do-nothing", r, expected_score=0, expected_passed=False)

    # Partial: only network group created, Maya Patel created
    r = verify_technician_group_routing_configuration(
        [], make_env_info({
            'network_group_found': True,
            'hardware_group_found': False,
            'maya_patel_found': True,
            'carlos_rivera_found': False,
            'ticket_1004_network_group': False,
            'ticket_1001_hardware_group': False,
            'ticket_1004_group_name': '',
            'ticket_1001_group_name': '',
            'maya_count_sql': 1, 'maya_patel_found_api': True,
            'carlos_count_sql': 0, 'carlos_rivera_found_api': False,
        }), {}
    )
    # 20 (network group) + 20 (Maya) = 40 pts, not passing
    all_ok &= assert_score("partial-one-group", r, expected_score=40, expected_passed=False)

    # Full pass: both groups, both technicians, both tickets routed
    r = verify_technician_group_routing_configuration(
        [], make_env_info({
            'network_group_found': True,
            'hardware_group_found': True,
            'maya_patel_found': True,
            'carlos_rivera_found': True,
            'ticket_1004_network_group': True,
            'ticket_1001_hardware_group': True,
            'ticket_1004_group_name': 'Network Operations Team',
            'ticket_1001_group_name': 'Hardware Support Team',
            'maya_count_sql': 1, 'maya_patel_found_api': True,
            'carlos_count_sql': 1, 'carlos_rivera_found_api': True,
        }), {}
    )
    # 20 + 20 + 20 + 20 + 10 + 10 = 100 pts
    all_ok &= assert_score("full-pass", r, expected_score=100, expected_passed=True)

    # ===== TASK 3: change_request_full_lifecycle =====
    print("\n[Task 3] change_request_full_lifecycle")

    # Do-nothing: no change found
    r = verify_change_request_full_lifecycle(
        [], make_env_info({
            'change_found': False,
            'change_id': '',
            'change_title_api': '',
            'change_type_name': '',
            'change_task_count': 0,
            'vpn_ticket_linked': False,
            'linked_request_ids_api': [],
            'change_status_is_requested': False,
            'change_status_name': '',
            'has_reason': False,
            'has_rollout_plan': False,
            'has_backout_plan': False,
        }), {}
    )
    all_ok &= assert_score("do-nothing", r, expected_score=0, expected_passed=False)

    # Partial: change created but nothing else done
    r = verify_change_request_full_lifecycle(
        [], make_env_info({
            'change_found': True,
            'change_id': '7',
            'change_title_api': 'Campus Network Core Switch Replacement - Buildings A and B',
            'change_type_name': 'Normal',
            'change_task_count': 0,
            'vpn_ticket_linked': False,
            'linked_request_ids_api': [],
            'change_status_is_requested': False,
            'change_status_name': 'Open',
            'has_reason': False,
            'has_rollout_plan': False,
            'has_backout_plan': False,
        }), {}
    )
    # 30 (change created) only, not passing
    all_ok &= assert_score("partial-just-change", r, expected_score=30, expected_passed=False)

    # Full pass: change + tasks + VPN linked + requested + reason+plan
    r = verify_change_request_full_lifecycle(
        [], make_env_info({
            'change_found': True,
            'change_id': '7',
            'change_title_api': 'Campus Network Core Switch Replacement - Buildings A and B',
            'change_type_name': 'Normal',
            'change_task_count': 2,
            'vpn_ticket_linked': True,
            'linked_request_ids_api': ['1004'],
            'change_status_is_requested': True,
            'change_status_name': 'Requested',
            'has_reason': True,
            'has_rollout_plan': True,
            'has_backout_plan': True,
        }), {}
    )
    # 30 + 20 + 20 + 20 + 10 = 100 pts
    all_ok &= assert_score("full-pass", r, expected_score=100, expected_passed=True)

    # ===== TASK 4: service_catalog_department_setup =====
    print("\n[Task 4] service_catalog_department_setup")

    # Do-nothing: nothing created
    r = verify_service_catalog_department_setup(
        [], make_env_info({
            'dept_created': False,
            'category_created': False,
            'subcat_hpc_created': False,
            'subcat_storage_created': False,
            'subcat_software_created': False,
            'subcategories_created_count': 0,
            'group_created': False,
            'template_created': False,
        }), {}
    )
    all_ok &= assert_score("do-nothing", r, expected_score=0, expected_passed=False)

    # Partial: only category + 1 subcategory (below 60)
    r = verify_service_catalog_department_setup(
        [], make_env_info({
            'dept_created': False,
            'category_created': True,
            'subcat_hpc_created': True,
            'subcat_storage_created': False,
            'subcat_software_created': False,
            'subcategories_created_count': 1,
            'group_created': False,
            'template_created': False,
        }), {}
    )
    # 20 (category) + 10 (HPC subcat) = 30 pts, not passing
    all_ok &= assert_score("partial-cat-one-subcat", r, expected_score=30, expected_passed=False)

    # Partial-pass: category + all 3 subcategories + group (just passes)
    r = verify_service_catalog_department_setup(
        [], make_env_info({
            'dept_created': False,
            'category_created': True,
            'subcat_hpc_created': True,
            'subcat_storage_created': True,
            'subcat_software_created': True,
            'subcategories_created_count': 3,
            'group_created': True,
            'template_created': False,
        }), {}
    )
    # 20 + 30 + 20 = 70 pts, passes
    all_ok &= assert_score("partial-pass-no-dept-no-template", r, expected_score=70, expected_passed=True)

    # Full pass
    r = verify_service_catalog_department_setup(
        [], make_env_info({
            'dept_created': True,
            'category_created': True,
            'subcat_hpc_created': True,
            'subcat_storage_created': True,
            'subcat_software_created': True,
            'subcategories_created_count': 3,
            'group_created': True,
            'template_created': True,
        }), {}
    )
    # 15 + 20 + 30 + 20 + 15 = 100 pts
    all_ok &= assert_score("full-pass", r, expected_score=100, expected_passed=True)

    # ===== TASK 5: incident_resolution_knowledge_base =====
    print("\n[Task 5] incident_resolution_knowledge_base")

    # Do-nothing: nothing changed
    r = verify_incident_resolution_knowledge_base(
        [], make_env_info({
            'status_1002': 2,
            'status_1005': 2,
            'status_name_1002': 'Open',
            'status_name_1005': 'Open',
            'ticket_1002_resolved': False,
            'ticket_1005_resolved': False,
            'ticket_1002_closed': False,
            'smtp_in_resolution_1002': 0,
            'acrobat_in_resolution_1005': 0,
            'kb_smtp_article_exists': False,
        }), {}
    )
    all_ok &= assert_score("do-nothing", r, expected_score=0, expected_passed=False)

    # Partial: 1002 resolved but not closed, no KB
    r = verify_incident_resolution_knowledge_base(
        [], make_env_info({
            'status_1002': 3,   # 3 = Resolved
            'status_1005': 2,
            'status_name_1002': 'Resolved',
            'status_name_1005': 'Open',
            'ticket_1002_resolved': True,
            'ticket_1005_resolved': False,
            'ticket_1002_closed': False,
            'smtp_in_resolution_1002': 1,
            'acrobat_in_resolution_1005': 0,
            'kb_smtp_article_exists': False,
        }), {}
    )
    # 25 + 5 (smtp bonus) = 30 pts, not passing
    all_ok &= assert_score("partial-resolved-1002-smtp", r, expected_score=30, expected_passed=False)

    # Partial-pass: 1002 resolved+closed + KB article (no 1005)
    r = verify_incident_resolution_knowledge_base(
        [], make_env_info({
            'status_1002': 4,   # 4 = Closed
            'status_1005': 2,
            'status_name_1002': 'Closed',
            'status_name_1005': 'Open',
            'ticket_1002_resolved': True,
            'ticket_1005_resolved': False,
            'ticket_1002_closed': True,
            'smtp_in_resolution_1002': 1,
            'acrobat_in_resolution_1005': 0,
            'kb_smtp_article_exists': True,
        }), {}
    )
    # 30 (1002 resolved+smtp) + 15 (closed) + 30 (KB) = 75 pts, passes
    all_ok &= assert_score("partial-pass-1002+KB", r, expected_score=75, expected_passed=True)

    # Full pass with all bonuses
    r = verify_incident_resolution_knowledge_base(
        [], make_env_info({
            'status_1002': 4,
            'status_1005': 3,
            'status_name_1002': 'Closed',
            'status_name_1005': 'Resolved',
            'ticket_1002_resolved': True,
            'ticket_1005_resolved': True,
            'ticket_1002_closed': True,
            'smtp_in_resolution_1002': 1,
            'acrobat_in_resolution_1005': 1,
            'kb_smtp_article_exists': True,
        }), {}
    )
    # (25+5) + (20+5) + 15 + 30 = 100, capped at 100
    all_ok &= assert_score("full-pass-all-bonuses", r, expected_score=100, expected_passed=True)

    print("\n" + "=" * 70)
    if all_ok:
        print("ALL OFFLINE PHASE 5 TESTS PASSED")
    else:
        print("SOME TESTS FAILED — review output above")
        sys.exit(1)


if __name__ == '__main__':
    run_all()
