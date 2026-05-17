#!/usr/bin/env python3
"""Offline unit tests for the 5 new odoo_hr_env verifiers.

Run with:
    cd /Users/pranjal/Developer/gym-anything
    python3 benchmarks/cua_world/environments/odoo_hr_env/tasks/_test_verifiers.py

No Odoo instance required — copy_from_env is mocked.
"""

import importlib.util
import json
import os
import sys

TASK_DIR = os.path.dirname(__file__)
FAILURES = []


def load_verifier(task_name):
    path = os.path.join(TASK_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location('verifier', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_env(result_data):
    def copy_from_env(src, dst):
        with open(dst, 'w') as f:
            json.dump(result_data, f)
    return {'copy_from_env': copy_from_env}


def make_env_missing():
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file: {src}")
    return {'copy_from_env': copy_from_env}


def check(label, r, *, expect_pass, score_min=None, score_max=None, score_exact=None):
    ok = True
    if r['passed'] != expect_pass:
        print(f"  FAIL {label}: passed={r['passed']}, want {expect_pass}; feedback={r['feedback']}")
        ok = False
    if score_exact is not None and r['score'] != score_exact:
        print(f"  FAIL {label}: score={r['score']}, want exactly {score_exact}")
        ok = False
    if score_min is not None and r['score'] < score_min:
        print(f"  FAIL {label}: score={r['score']}, want >={score_min}")
        ok = False
    if score_max is not None and r['score'] > score_max:
        print(f"  FAIL {label}: score={r['score']}, want <={score_max}")
        ok = False
    if ok:
        print(f"  OK   {label}: score={r['score']} passed={r['passed']}")
    else:
        FAILURES.append(label)


TASK_INFO = {}

# ─────────────────────────────────────────────────────────────────────────────
# Task 1: restructure_division_merger
#   Pass >= 60.  AP4 max_partial = 30 (2/3 C1 + 1 C2 job).
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== T1: restructure_division_merger ===")
mod = load_verifier('restructure_division_merger')
fn  = mod.verify_restructure_division_merger

RND, LTP, RONNIE         = 1, 2, 6
SENIOR_DEV, DEV, PROJ    = 3, 4, 5
ERNEST_ID, PAUL_ID, RAND = 10, 11, 12
GT1 = {'rnd_dept_id': RND, 'ltp_dept_id': LTP,
       'ernest_id': ERNEST_ID, 'paul_id': PAUL_ID, 'randall_id': RAND,
       'ronnie_id': RONNIE,
       'senior_dev_id': SENIOR_DEV, 'developer_id': DEV, 'project_lead_id': PROJ}

# Do-nothing: all employees in LTP, wrong jobs, no RnD manager, LTP active
r = fn([], make_env({
    'ernest':  {'dept_id': LTP, 'dept_name': 'Long Term Projects', 'job_id': 99, 'job_name': 'Consultant', 'mgr_id': None, 'coach_id': None},
    'paul':    {'dept_id': LTP, 'dept_name': 'Long Term Projects', 'job_id': 99, 'job_name': 'Consultant', 'mgr_id': None, 'coach_id': None},
    'randall': {'dept_id': LTP, 'dept_name': 'Long Term Projects', 'job_id': 99, 'job_name': 'Consultant', 'mgr_id': None, 'coach_id': None},
    'rnd_dept_manager_id': None, 'rnd_dept_manager_name': None,
    'ltp_active': True,
    'gt': GT1,
}), TASK_INFO)
check('T1 do-nothing', r, expect_pass=False, score_exact=0)

# Partial: only Ernest in RnD+SeniorDev (10+10=20 pts)
r = fn([], make_env({
    'ernest':  {'dept_id': RND, 'dept_name': 'Research & Development', 'job_id': SENIOR_DEV, 'job_name': 'Senior Developer', 'mgr_id': None, 'coach_id': None},
    'paul':    {'dept_id': LTP, 'dept_name': 'Long Term Projects',     'job_id': 99, 'job_name': 'Consultant', 'mgr_id': None, 'coach_id': None},
    'randall': {'dept_id': LTP, 'dept_name': 'Long Term Projects',     'job_id': 99, 'job_name': 'Consultant', 'mgr_id': None, 'coach_id': None},
    'rnd_dept_manager_id': None, 'rnd_dept_manager_name': None,
    'ltp_active': True,
    'gt': GT1,
}), TASK_INFO)
check('T1 partial (20 pts)', r, expect_pass=False, score_min=1, score_max=59)

# AP4: max partial = 20 (2 employees in RnD) + 10 (one job) = 30 < 60
r = fn([], make_env({
    'ernest':  {'dept_id': RND, 'job_id': SENIOR_DEV, 'job_name': 'Senior Developer', 'dept_name': 'R&D', 'mgr_id': None, 'coach_id': None},
    'paul':    {'dept_id': RND, 'job_id': DEV,         'job_name': 'Developer',        'dept_name': 'R&D', 'mgr_id': None, 'coach_id': None},
    'randall': {'dept_id': LTP, 'job_id': 99,           'job_name': 'Consultant',       'dept_name': 'LTP', 'mgr_id': None, 'coach_id': None},
    'rnd_dept_manager_id': None, 'rnd_dept_manager_name': None,
    'ltp_active': True,
    'gt': GT1,
}), TASK_INFO)
check('T1 AP4 max-partial (30 pts)', r, expect_pass=False, score_max=30)

# Full completion
r = fn([], make_env({
    'ernest':  {'dept_id': RND, 'job_id': SENIOR_DEV, 'job_name': 'Senior Developer', 'dept_name': 'R&D', 'mgr_id': None, 'coach_id': None},
    'paul':    {'dept_id': RND, 'job_id': DEV,         'job_name': 'Developer',        'dept_name': 'R&D', 'mgr_id': None, 'coach_id': ERNEST_ID},
    'randall': {'dept_id': RND, 'job_id': PROJ,         'job_name': 'Project Lead',     'dept_name': 'R&D', 'mgr_id': None, 'coach_id': None},
    'rnd_dept_manager_id': RONNIE, 'rnd_dept_manager_name': 'Ronnie Hart',
    'ltp_active': False,
    'gt': GT1,
}), TASK_INFO)
check('T1 full (100 pts)', r, expect_pass=True, score_min=60)

# Missing file
r = fn([], make_env_missing(), TASK_INFO)
check('T1 missing', r, expect_pass=False, score_exact=0)

# ─────────────────────────────────────────────────────────────────────────────
# Task 2: leave_audit_q3_corrections
#   Pass >= 65.  AP4 max_partial = 10 (C4 partial).
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== T2: leave_audit_q3_corrections ===")
mod = load_verifier('leave_audit_q3_corrections')
fn  = mod.verify_leave_audit_q3_corrections

GT2 = {'pto_leave_type_id': 10, 'ernest_leave_id': 20, 'ronnie_leave_id': 21,
       'eli_id': 30, 'walter_id': 31, 'walter_alloc_id': 40}

# Do-nothing: all wrong, no Eli allocation, Walter at 20 days
r = fn([], make_env({
    'pto_validation_type': 'no_validation',
    'ernest_leave_state':  'confirm',
    'ronnie_leave_state':  'confirm',
    'eli_pto_allocations': [],
    'walter_alloc_days':   20,
    'walter_alloc_state':  'validate',
    'gt': GT2,
}), TASK_INFO)
check('T2 do-nothing', r, expect_pass=False, score_exact=0)

# Partial C1 + C2 only (25 + 15 = 40)
r = fn([], make_env({
    'pto_validation_type': 'manager',
    'ernest_leave_state':  'refuse',
    'ronnie_leave_state':  'confirm',
    'eli_pto_allocations': [],
    'walter_alloc_days':   20,
    'walter_alloc_state':  'validate',
    'gt': GT2,
}), TASK_INFO)
check('T2 partial C1+C2 (40 pts)', r, expect_pass=False, score_min=1, score_max=64)

# AP4: C4 partial only (10 pts) — must not pass
r = fn([], make_env({
    'pto_validation_type': 'no_validation',
    'ernest_leave_state':  'confirm',
    'ronnie_leave_state':  'confirm',
    'eli_pto_allocations': [{'number_of_days': 10, 'state': 'draft', 'number_of_days_display': '10'}],
    'walter_alloc_days':   20,
    'walter_alloc_state':  'validate',
    'gt': GT2,
}), TASK_INFO)
check('T2 AP4 max-partial (10 pts)', r, expect_pass=False, score_max=10)

# Full
r = fn([], make_env({
    'pto_validation_type': 'manager',
    'ernest_leave_state':  'refuse',
    'ronnie_leave_state':  'refuse',
    'eli_pto_allocations': [{'number_of_days': 15, 'state': 'validate', 'number_of_days_display': '15'}],
    'walter_alloc_days':   15,
    'walter_alloc_state':  'validate',
    'gt': GT2,
}), TASK_INFO)
check('T2 full (100 pts)', r, expect_pass=True, score_min=65)

# ─────────────────────────────────────────────────────────────────────────────
# Task 3: recruitment_q2_pipeline_cleanup
#   Pass >= 65.  AP4 max_partial = 10 (C3 one-side).
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== T3: recruitment_q2_pipeline_cleanup ===")
mod = load_verifier('recruitment_q2_pipeline_cleanup')
fn  = mod.verify_recruitment_q2_pipeline_cleanup

# Do-nothing
r = fn([], make_env({
    'ta_sequence': 3, 'first_interview_seq': 10, 'second_interview_seq': 20,
    'cameron_active': True,
    'thomas_sds_active': True, 'thomas_expdev_active': True,
    'sofia_hired': False, 'sofia_at_contract_signed': False, 'sofia_emp_id': None,
    'gt': {},
}), TASK_INFO)
check('T3 do-nothing', r, expect_pass=False, score_exact=0)

# AP4: C3 one-side (SDS archived but ExpDev also archived) = 10 pts
r = fn([], make_env({
    'ta_sequence': 3, 'first_interview_seq': 10, 'second_interview_seq': 20,
    'cameron_active': True,
    'thomas_sds_active': False, 'thomas_expdev_active': False,  # both archived (wrong)
    'sofia_hired': False, 'sofia_at_contract_signed': False, 'sofia_emp_id': None,
    'gt': {},
}), TASK_INFO)
check('T3 AP4 max-partial (10 pts)', r, expect_pass=False, score_max=10)

# Full
r = fn([], make_env({
    'ta_sequence': 15, 'first_interview_seq': 10, 'second_interview_seq': 20,
    'cameron_active': False,
    'thomas_sds_active': False, 'thomas_expdev_active': True,
    'sofia_hired': True, 'sofia_at_contract_signed': True, 'sofia_emp_id': 42,
    'gt': {},
}), TASK_INFO)
check('T3 full (100 pts)', r, expect_pass=True, score_min=65)

# ─────────────────────────────────────────────────────────────────────────────
# Task 4: expense_monthly_audit_june
#   Pass >= 65.  AP4 max_partial = 10 (C2 submitted partial).
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== T4: expense_monthly_audit_june ===")
mod = load_verifier('expense_monthly_audit_june')
fn  = mod.verify_expense_monthly_audit_june

# Do-nothing
r = fn([], make_env({
    'conf_can_be_expensed': False,
    'eli_sheet_state': 'draft',
    'rachel_sheet_state': 'submit',
    'marc_sheet_state': 'submit',
    'gt': {},
}), TASK_INFO)
check('T4 do-nothing', r, expect_pass=False, score_exact=0)

# AP4: Eli submitted only (10 pts partial)
r = fn([], make_env({
    'conf_can_be_expensed': False,
    'eli_sheet_state': 'submit',
    'rachel_sheet_state': 'submit',
    'marc_sheet_state': 'submit',
    'gt': {},
}), TASK_INFO)
check('T4 AP4 max-partial (10 pts)', r, expect_pass=False, score_max=10)

# Full
r = fn([], make_env({
    'conf_can_be_expensed': True,
    'eli_sheet_state': 'approve',
    'rachel_sheet_state': 'cancel',
    'marc_sheet_state': 'cancel',
    'gt': {},
}), TASK_INFO)
check('T4 full (100 pts)', r, expect_pass=True, score_min=65)

# ─────────────────────────────────────────────────────────────────────────────
# Task 5: employee_departure_management
#   Pass >= 65.  AP4 max_partial = 15 (C1a only).
# ─────────────────────────────────────────────────────────────────────────────
print("\n=== T5: employee_departure_management ===")
mod = load_verifier('employee_departure_management')
fn  = mod.verify_employee_departure_management

TINA = 50
GT5 = {'tina_id': TINA, 'rachel_id': 51, 'doris_id': 52, 'tina_sheet_id': 100}

# Do-nothing
r = fn([], make_env({
    'rachel_reassigned': False, 'doris_reassigned': False,
    'rachel_parent_id': TINA, 'doris_parent_id': TINA,
    'tina_sheet_state': 'submit',
    'tina_active': True,
    'departure_reason_id': None, 'departure_date': None,
    'leave_note_found': False,
    'gt': GT5,
}), TASK_INFO)
check('T5 do-nothing', r, expect_pass=False, score_exact=0)

# AP4: C1a only (15 pts)
r = fn([], make_env({
    'rachel_reassigned': True, 'doris_reassigned': False,
    'rachel_parent_id': 99, 'doris_parent_id': TINA,
    'tina_sheet_state': 'submit',
    'tina_active': True,
    'departure_reason_id': None, 'departure_date': None,
    'leave_note_found': False,
    'gt': GT5,
}), TASK_INFO)
check('T5 AP4 max-partial (15 pts)', r, expect_pass=False, score_max=15)

# Full
r = fn([], make_env({
    'rachel_reassigned': True, 'doris_reassigned': True,
    'rachel_parent_id': 99, 'doris_parent_id': 99,
    'tina_sheet_state': 'cancel',
    'tina_active': False,
    'departure_reason_id': 1, 'departure_date': '2025-06-16',
    'leave_note_found': True,
    'gt': GT5,
}), TASK_INFO)
check('T5 full (100 pts)', r, expect_pass=True, score_min=65)

# Missing file test
r = fn([], make_env_missing(), TASK_INFO)
check('T5 missing', r, expect_pass=False, score_exact=0)

# ─────────────────────────────────────────────────────────────────────────────
print()
if FAILURES:
    print(f"FAILED: {len(FAILURES)} test(s): {FAILURES}")
    sys.exit(1)
else:
    print("✓ All offline verifier tests passed.")
