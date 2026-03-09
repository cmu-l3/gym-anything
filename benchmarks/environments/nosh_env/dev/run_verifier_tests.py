#!/usr/bin/env python3
"""
Offline verifier tests for all 5 new nosh_env tasks.
Tests: do-nothing (score=0), wrong-target (score=0), partial (0 < score < threshold), full (score>=threshold).
"""
import sys, os, json, shutil, tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')

TASKS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'tasks')


def make_copy_fn(data):
    tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(data, tmp)
    tmp.close()

    def copy_fn(src, dst):
        shutil.copy(tmp.name, dst)

    copy_fn._tmp = tmp.name
    return copy_fn


def call_verifier(task_name, func_name, data, task_info=None):
    import importlib.util
    vpath = os.path.join(TASKS_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location(f"{task_name}_verifier", vpath)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    func = getattr(mod, func_name)
    copy_fn = make_copy_fn(data)
    try:
        result = func(traj={}, env_info={'copy_from_env': copy_fn}, task_info=task_info or {})
    finally:
        os.unlink(copy_fn._tmp)
    return result


def assert_test(label, result, expect_passed, expect_score_fn, note=""):
    passed_ok = result['passed'] == expect_passed
    score_ok = expect_score_fn(result['score'])
    status = "PASS" if (passed_ok and score_ok) else "FAIL"
    detail = f"passed={result['passed']}, score={result['score']}"
    if note:
        detail += f" | {note}"
    print(f"  [{status}] {label}: {detail}")
    if not (passed_ok and score_ok):
        print(f"         feedback: {result.get('feedback','')[:200]}")
    return passed_ok and score_ok


all_ok = True


# =============================================================================
# TASK 1: hypertension_panel_remediation
# =============================================================================
print("\n=== TASK 1: hypertension_panel_remediation ===")

# Do-nothing: empty patients dict
r = call_verifier('hypertension_panel_remediation', 'verify_hypertension_panel_remediation', {
    "task_start": 1000, "patients": {}, "noise": {}
})
ok = assert_test("DO-NOTHING", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Wrong-target: treat pid 99 (not in the task) instead of real pids
r = call_verifier('hypertension_panel_remediation', 'verify_hypertension_panel_remediation', {
    "task_start": 1000,
    "patients": {
        "22": {"any_antihtn_found": False, "new_rx": False, "new_encounter": False},
        "23": {"any_antihtn_found": False, "new_rx": False, "new_encounter": False},
        "24": {"any_antihtn_found": False, "new_rx": False, "new_encounter": False},
        "99": {"any_antihtn_found": True, "new_rx": True, "new_encounter": True},
    }
})
ok = assert_test("WRONG-TARGET (pid 99 treated, real pids untouched)", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Partial: only pid 22 treated (25 pts) < 60 threshold
r = call_verifier('hypertension_panel_remediation', 'verify_hypertension_panel_remediation', {
    "task_start": 1000,
    "patients": {
        "22": {"any_antihtn_found": True, "new_rx": True, "drug_name": "Amlodipine",
               "new_encounter": True},
        "23": {"any_antihtn_found": False, "new_rx": False, "new_encounter": False},
        "24": {"any_antihtn_found": False, "new_rx": False, "new_encounter": False},
    }
})
ok = assert_test("PARTIAL (1/3 patients, expect 0<score<60)", r, False, lambda s: 0 < s < 60)
all_ok = all_ok and ok

# Full: all 3 treated
r = call_verifier('hypertension_panel_remediation', 'verify_hypertension_panel_remediation', {
    "task_start": 1000,
    "patients": {
        "22": {"any_antihtn_found": True, "new_rx": True, "drug_name": "Amlodipine",
               "new_encounter": True},
        "23": {"any_antihtn_found": True, "new_rx": True, "drug_name": "Amlodipine",
               "new_encounter": True},
        "24": {"any_antihtn_found": True, "new_rx": True, "drug_name": "Amlodipine",
               "new_encounter": True},
    }
})
ok = assert_test("FULL COMPLETION (all 3, expect score>=60, passed=True)", r, True, lambda s: s >= 60)
all_ok = all_ok and ok


# =============================================================================
# TASK 2: vaccine_audit_and_schedule
# =============================================================================
print("\n=== TASK 2: vaccine_audit_and_schedule ===")

# Do-nothing
r = call_verifier('vaccine_audit_and_schedule', 'verify_vaccine_audit_and_schedule', {
    "task_start": 1000, "patients": {}, "noise_pid30": {}
})
ok = assert_test("DO-NOTHING", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Wrong-target: vaccinate pid 30 (noise) only, leave 27/28/29 unvaccinated
r = call_verifier('vaccine_audit_and_schedule', 'verify_vaccine_audit_and_schedule', {
    "task_start": 1000,
    "patients": {
        "27": {"shingrix_found": False, "new_vaccine_added": False, "appointment_sep15": False},
        "28": {"shingrix_found": False, "new_vaccine_added": False, "appointment_sep15": False},
        "29": {"shingrix_found": False, "new_vaccine_added": False, "appointment_sep15": False},
    },
    "noise_pid30": {"name": "Clarence Webb", "shingrix_count": 2}  # duplicate, not scored
})
ok = assert_test("WRONG-TARGET (pid 30 extra, real pids untouched)", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Partial: 1 patient complete (15+10=25 pts) < 60 threshold
r = call_verifier('vaccine_audit_and_schedule', 'verify_vaccine_audit_and_schedule', {
    "task_start": 1000,
    "patients": {
        "27": {"shingrix_found": True, "new_vaccine_added": True, "appointment_sep15": True},
        "28": {"shingrix_found": False, "new_vaccine_added": False, "appointment_sep15": False},
        "29": {"shingrix_found": False, "new_vaccine_added": False, "appointment_sep15": False},
    }
})
ok = assert_test("PARTIAL (1/3 complete, expect 0<score<60)", r, False, lambda s: 0 < s < 60)
all_ok = all_ok and ok

# Full: all 3 complete + bonus = 100 pts
r = call_verifier('vaccine_audit_and_schedule', 'verify_vaccine_audit_and_schedule', {
    "task_start": 1000,
    "patients": {
        "27": {"shingrix_found": True, "new_vaccine_added": True, "appointment_sep15": True},
        "28": {"shingrix_found": True, "new_vaccine_added": True, "appointment_sep15": True},
        "29": {"shingrix_found": True, "new_vaccine_added": True, "appointment_sep15": True},
    }
})
ok = assert_test("FULL COMPLETION (all 3 + bonus, expect score>=60, passed=True)", r, True, lambda s: s >= 60)
all_ok = all_ok and ok


# =============================================================================
# TASK 3: post_visit_documentation_workflow
# =============================================================================
print("\n=== TASK 3: post_visit_documentation_workflow ===")

# Do-nothing
r = call_verifier('post_visit_documentation_workflow', 'verify_post_visit_documentation_workflow', {
    "task_start": 1000,
    "patient_pid": 31,
    "encounter": {"new_encounter": False, "today_encounter": False},
    "vitals": {"new_vitals": False},
    "problem": {"new_problem": False, "j069_found": False},
    "allergy": {"new_allergy": False, "penicillin_found": False},
    "rx": {"new_rx": False, "azithromycin_found": False},
    "appointment": {"new_appointment": False, "jul08_found": False},
}, task_info={'metadata': {'patient_pid': 31}})
ok = assert_test("DO-NOTHING", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Wrong-target: correct PID but entirely wrong patient checked (expect 0 score from empty checks)
r = call_verifier('post_visit_documentation_workflow', 'verify_post_visit_documentation_workflow', {
    "task_start": 1000,
    "patient_pid": 99,  # wrong pid — verifier should catch this
    "encounter": {"new_encounter": True, "today_encounter": True},
    "vitals": {"new_vitals": True, "weight": "134", "height": "65",
               "bp_systolic": "112", "bp_diastolic": "72", "pulse": "74"},
    "problem": {"new_problem": True, "j069_found": True},
    "allergy": {"new_allergy": True, "penicillin_found": True},
    "rx": {"new_rx": True, "azithromycin_found": True, "dosage": "500mg"},
    "appointment": {"new_appointment": True, "jul08_found": True},
}, task_info={'metadata': {'patient_pid': 31}})
ok = assert_test("WRONG-TARGET (pid=99 in result, expect score=0)", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Partial: encounter + vitals only (15+20=35 pts) < 70 threshold
r = call_verifier('post_visit_documentation_workflow', 'verify_post_visit_documentation_workflow', {
    "task_start": 1000,
    "patient_pid": 31,
    "encounter": {"new_encounter": True, "today_encounter": True},
    "vitals": {"new_vitals": True, "weight": "134", "height": "65",
               "bp_systolic": "112", "bp_diastolic": "72", "pulse": "74"},
    "problem": {"new_problem": False, "j069_found": False},
    "allergy": {"new_allergy": False, "penicillin_found": False},
    "rx": {"new_rx": False, "azithromycin_found": False},
    "appointment": {"new_appointment": False, "jul08_found": False},
}, task_info={'metadata': {'patient_pid': 31}})
ok = assert_test("PARTIAL (encounter+vitals only, expect 0<score<70)", r, False, lambda s: 0 < s < 70)
all_ok = all_ok and ok

# Full: all criteria met = 100 pts
r = call_verifier('post_visit_documentation_workflow', 'verify_post_visit_documentation_workflow', {
    "task_start": 1000,
    "patient_pid": 31,
    "encounter": {"new_encounter": True, "today_encounter": True},
    "vitals": {"new_vitals": True, "weight": "134", "height": "65",
               "bp_systolic": "112", "bp_diastolic": "72", "pulse": "74"},
    "problem": {"new_problem": True, "j069_found": True, "latest_name": "Acute URTI"},
    "allergy": {"new_allergy": True, "penicillin_found": True, "latest_allergen": "Penicillin"},
    "rx": {"new_rx": True, "azithromycin_found": True, "dosage": "500mg", "latest_drug": "Azithromycin"},
    "appointment": {"new_appointment": True, "jul08_found": True, "latest_start": "2026-07-08"},
}, task_info={'metadata': {'patient_pid': 31}})
ok = assert_test("FULL COMPLETION (expect score>=70, passed=True)", r, True, lambda s: s >= 70)
all_ok = all_ok and ok


# =============================================================================
# TASK 4: allergy_drug_conflict_resolution
# =============================================================================
print("\n=== TASK 4: allergy_drug_conflict_resolution ===")

# Do-nothing
r = call_verifier('allergy_drug_conflict_resolution', 'verify_allergy_drug_conflict_resolution', {
    "task_start": 1000,
    "patients": {
        "32": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
        "33": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
        "34": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
    }
})
ok = assert_test("DO-NOTHING", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Wrong-target: discontinue pid 35 (noise) instead of conflict patients
r = call_verifier('allergy_drug_conflict_resolution', 'verify_allergy_drug_conflict_resolution', {
    "task_start": 1000,
    "patients": {
        "32": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
        "33": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
        "34": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
    },
    "noise_pid35": {"allergy_drug_inactive": True}  # noise treated, not scored
})
ok = assert_test("WRONG-TARGET (pid 35 treated, real conflicts untouched)", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Partial: 1/3 conflicts resolved (20 pts) < 60 threshold
r = call_verifier('allergy_drug_conflict_resolution', 'verify_allergy_drug_conflict_resolution', {
    "task_start": 1000,
    "patients": {
        "32": {"conflicting_drug_inactive": True, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 0,
               "alternative_prescribed": False, "new_encounter": False},
        "33": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
        "34": {"conflicting_drug_inactive": False, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 1,
               "alternative_prescribed": False, "new_encounter": False},
    }
})
ok = assert_test("PARTIAL (1/3 discontinued only, expect 0<score<60)", r, False, lambda s: 0 < s < 60)
all_ok = all_ok and ok

# Full: all 3 conflicts resolved + alternatives + encounters = 100 pts
r = call_verifier('allergy_drug_conflict_resolution', 'verify_allergy_drug_conflict_resolution', {
    "task_start": 1000,
    "patients": {
        "32": {"conflicting_drug_inactive": True, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 0,
               "alternative_prescribed": True, "alternative_drug": "Nitrofurantoin",
               "new_encounter": True},
        "33": {"conflicting_drug_inactive": False, "conflicting_drug_removed": True,
               "init_active_rx": 1, "curr_active_rx": 0,
               "alternative_prescribed": True, "alternative_drug": "Azithromycin",
               "new_encounter": True},
        "34": {"conflicting_drug_inactive": True, "conflicting_drug_removed": False,
               "init_active_rx": 1, "curr_active_rx": 0,
               "alternative_prescribed": True, "alternative_drug": "Acetaminophen",
               "new_encounter": True},
    }
})
ok = assert_test("FULL COMPLETION (all 3 + alternatives + encounters, expect score>=60)", r, True, lambda s: s >= 60)
all_ok = all_ok and ok


# =============================================================================
# TASK 5: diabetic_care_gap_intervention
# =============================================================================
print("\n=== TASK 5: diabetic_care_gap_intervention ===")

# Do-nothing
r = call_verifier('diabetic_care_gap_intervention', 'verify_diabetic_care_gap_intervention', {
    "task_start": 1000,
    "patients": {
        "36": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
        "37": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
        "38": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
    }
})
ok = assert_test("DO-NOTHING", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Wrong-target: vaccinate noise patients 39/40 (not scored), leave care-gap pids untouched
r = call_verifier('diabetic_care_gap_intervention', 'verify_diabetic_care_gap_intervention', {
    "task_start": 1000,
    "patients": {
        "36": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
        "37": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
        "38": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
    },
    "noise": {
        "39": {"flu_count": 2},  # agent vaccinated noise patient (extra, not penalized but not scored)
        "40": {"flu_count": 2},
    }
})
ok = assert_test("WRONG-TARGET (noise pids vaccinated, care-gap pids untouched)", r, False, lambda s: s == 0)
all_ok = all_ok and ok

# Partial: 1/3 vaccinated + encounter (20+10=30 pts) < 60 threshold
r = call_verifier('diabetic_care_gap_intervention', 'verify_diabetic_care_gap_intervention', {
    "task_start": 1000,
    "patients": {
        "36": {"flu_vaccine_added": True, "new_vaccine_added": True,
               "latest_vaccine_name": "Influenza, seasonal", "new_encounter": True},
        "37": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
        "38": {"flu_vaccine_added": False, "new_vaccine_added": False, "new_encounter": False},
    }
})
ok = assert_test("PARTIAL (1/3 vaccinated+encounter, expect 0<score<60)", r, False, lambda s: 0 < s < 60)
all_ok = all_ok and ok

# Full: all 3 vaccinated + encounters + bonus = 100 pts
r = call_verifier('diabetic_care_gap_intervention', 'verify_diabetic_care_gap_intervention', {
    "task_start": 1000,
    "patients": {
        "36": {"flu_vaccine_added": True, "new_vaccine_added": True,
               "latest_vaccine_name": "Influenza, seasonal", "new_encounter": True},
        "37": {"flu_vaccine_added": True, "new_vaccine_added": True,
               "latest_vaccine_name": "Influenza, seasonal", "new_encounter": True},
        "38": {"flu_vaccine_added": True, "new_vaccine_added": True,
               "latest_vaccine_name": "Influenza, seasonal", "new_encounter": True},
    }
})
ok = assert_test("FULL COMPLETION (all 3 + bonus, expect score>=60, passed=True)", r, True, lambda s: s >= 60)
all_ok = all_ok and ok


# =============================================================================
# Summary
# =============================================================================
print("\n" + "="*60)
if all_ok:
    print("ALL VERIFIER TESTS PASSED")
else:
    print("SOME VERIFIER TESTS FAILED — see above")
print("="*60)
sys.exit(0 if all_ok else 1)
