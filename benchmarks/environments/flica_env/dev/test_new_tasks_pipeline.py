#!/usr/bin/env python3
"""
Pipeline verification tests for the 5 new flica_env tasks (redesigned).

Tasks use 3-4 distinct FLICA app features each:
  1. crew_partner_network_setup:   display name + position(Captain) + home/base airports(ORD) + 3 friends
  2. reserve_crew_contact_setup:   display name + home/base airports(HOU) + 5 friends
  3. irregular_ops_crew_network:   display name + position(FO) + airports(BNA/MEM) + personalization(24h)
  4. new_hire_crew_onboarding:     display name + home/base airports(JFK) + 4 friends
  5. crew_scheduling_rep_setup:    display name + home/base airports(DFW) + personalization(calendar) + 3 friends

Tests each verifier with:
  1. Do-nothing   → copy_from_env raises (no JSON on device) → expect score=0, passed=False
  2. Partial      → JSON with some flags True                → expect 0 < score < pass_threshold
  3. Full         → JSON with all flags True                 → expect score=100, passed=True
  4. Wrong-target → JSON with all flags False                → expect score=0, passed=False

No Android VM required.
"""

import importlib.util
import json
import os
import sys

TASKS_DIR    = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tasks")
EVIDENCE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)


def _load_verifier(task_name):
    path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _copy_fn_from_json(data):
    def copy_fn(src_path, dest_path):
        with open(dest_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
    return copy_fn


def _copy_fn_raises():
    def copy_fn(src_path, dest_path):
        raise FileNotFoundError(f"No such file on device: {src_path}")
    return copy_fn


def _run(task_name, fn_name, result_data):
    mod = _load_verifier(task_name)
    fn  = getattr(mod, fn_name)
    task_json_path = os.path.join(TASKS_DIR, task_name, "task.json")
    with open(task_json_path) as f:
        task_info = json.load(f)
    if result_data is None:
        env_info = {"copy_from_env": _copy_fn_raises()}
    else:
        env_info = {"copy_from_env": _copy_fn_from_json(result_data)}
    return fn(traj=[], env_info=env_info, task_info=task_info)


results_summary = {}

# ===========================================================================
# TASK 1: crew_partner_network_setup
# United Airlines Captain, ORD
# Features: display name(25) + position=Captain(25) + home_airport(15) + base_airport(10) + 3 friends(9+8+8=25)
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 1: crew_partner_network_setup")
print("=" * 60)

TASK = "crew_partner_network_setup"
FN   = "verify_crew_partner_network_setup"

FULL_RESULT = {
    "display_name_found": True,
    "position_found": True,
    "home_airport_found": True,
    "base_airport_found": True,
    "friend1_found": True,
    "friend2_found": True,
    "friend3_found": True,
    "settings_reachable": True,
    "friends_reachable": True,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:     score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: name + position (50 pts < 60 threshold)
r_partial = _run(TASK, FN, {
    "display_name_found": True, "position_found": True,
    "home_airport_found": False, "base_airport_found": False,
    "friend1_found": False, "friend2_found": False, "friend3_found": False,
})
print(f"Partial (name+pos): score={r_partial['score']}, passed={r_partial['passed']}")
assert r_partial['score'] == 50 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full
r_full = _run(TASK, FN, FULL_RESULT)
print(f"Full:           score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target (all False)
r_wt = _run(TASK, FN, {k: False for k in FULL_RESULT})
print(f"Wrong-target:   score={r_wt['score']}, passed={r_wt['passed']}")
assert r_wt['score'] == 0 and not r_wt['passed'], f"FAIL wrong-target: {r_wt}"

results_summary[TASK] = "PASS"
print(f"=> crew_partner_network_setup: ALL TESTS PASSED")


# ===========================================================================
# TASK 2: reserve_crew_contact_setup
# Southwest Reserve Coordinator, HOU
# Features: display name(20) + home_airport(15) + base_airport(15) + 5 friends(10 each = 50)
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 2: reserve_crew_contact_setup")
print("=" * 60)

TASK = "reserve_crew_contact_setup"
FN   = "verify_reserve_crew_contact_setup"

FULL_RESULT = {
    "display_name_found": True,
    "home_airport_found": True,
    "base_airport_found": True,
    "friend1_found": True,
    "friend2_found": True,
    "friend3_found": True,
    "friend4_found": True,
    "friend5_found": True,
    "settings_reachable": True,
    "friends_reachable": True,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:     score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: name + home airport + 1 friend = 20+15+10 = 45 < 60
r_partial = _run(TASK, FN, {
    "display_name_found": True, "home_airport_found": True, "base_airport_found": False,
    "friend1_found": True, "friend2_found": False, "friend3_found": False,
    "friend4_found": False, "friend5_found": False,
})
print(f"Partial (name+home+1friend): score={r_partial['score']}, passed={r_partial['passed']}")
assert r_partial['score'] == 45 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full
r_full = _run(TASK, FN, FULL_RESULT)
print(f"Full:           score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target
r_wt = _run(TASK, FN, {k: False for k in FULL_RESULT})
print(f"Wrong-target:   score={r_wt['score']}, passed={r_wt['passed']}")
assert r_wt['score'] == 0 and not r_wt['passed'], f"FAIL wrong-target: {r_wt}"

results_summary[TASK] = "PASS"
print(f"=> reserve_crew_contact_setup: ALL TESTS PASSED")


# ===========================================================================
# TASK 3: irregular_ops_crew_network
# FedEx FO commuter, BNA -> MEM
# Features: display name(20) + position=FO(20) + home_airport BNA(20) + base_airport MEM(20) + 24h time(20)
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 3: irregular_ops_crew_network")
print("=" * 60)

TASK = "irregular_ops_crew_network"
FN   = "verify_irregular_ops_crew_network"

FULL_RESULT = {
    "display_name_found": True,
    "position_found": True,
    "home_airport_found": True,
    "base_airport_found": True,
    "personalization_found": True,
    "settings_reachable": True,
    "friends_reachable": True,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:     score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: name + position + airports (no personalization) = 20+20+20+20 = 80 → PASSES
# Let's try: just name + position = 40 < 60
r_partial = _run(TASK, FN, {
    "display_name_found": True, "position_found": True,
    "home_airport_found": False, "base_airport_found": False, "personalization_found": False,
})
print(f"Partial (name+pos): score={r_partial['score']}, passed={r_partial['passed']}")
assert r_partial['score'] == 40 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full
r_full = _run(TASK, FN, FULL_RESULT)
print(f"Full:           score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target
r_wt = _run(TASK, FN, {k: False for k in FULL_RESULT})
print(f"Wrong-target:   score={r_wt['score']}, passed={r_wt['passed']}")
assert r_wt['score'] == 0 and not r_wt['passed'], f"FAIL wrong-target: {r_wt}"

results_summary[TASK] = "PASS"
print(f"=> irregular_ops_crew_network: ALL TESTS PASSED")


# ===========================================================================
# TASK 4: new_hire_crew_onboarding
# JetBlue new hire FA, JFK
# Features: display name(20) + home_airport JFK(20) + base_airport JFK(20) + 4 friends(10 each = 40)
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 4: new_hire_crew_onboarding")
print("=" * 60)

TASK = "new_hire_crew_onboarding"
FN   = "verify_new_hire_crew_onboarding"

FULL_RESULT = {
    "display_name_found": True,
    "home_airport_found": True,
    "base_airport_found": True,
    "friend1_found": True,
    "friend2_found": True,
    "friend3_found": True,
    "friend4_found": True,
    "settings_reachable": True,
    "friends_reachable": True,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:     score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: name + 2 friends = 20+10+10 = 40 < 60
r_partial = _run(TASK, FN, {
    "display_name_found": True, "home_airport_found": False, "base_airport_found": False,
    "friend1_found": True, "friend2_found": True, "friend3_found": False, "friend4_found": False,
})
print(f"Partial (name+2friends): score={r_partial['score']}, passed={r_partial['passed']}")
assert r_partial['score'] == 40 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full
r_full = _run(TASK, FN, FULL_RESULT)
print(f"Full:           score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target
r_wt = _run(TASK, FN, {k: False for k in FULL_RESULT})
print(f"Wrong-target:   score={r_wt['score']}, passed={r_wt['passed']}")
assert r_wt['score'] == 0 and not r_wt['passed'], f"FAIL wrong-target: {r_wt}"

results_summary[TASK] = "PASS"
print(f"=> new_hire_crew_onboarding: ALL TESTS PASSED")


# ===========================================================================
# TASK 5: crew_scheduling_rep_setup
# AA Scheduling Rep, DFW
# Features: display name(20) + home_airport DFW(15) + base_airport DFW(15) + personalization=calendar(20) + 3 friends(10 each = 30)
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 5: crew_scheduling_rep_setup")
print("=" * 60)

TASK = "crew_scheduling_rep_setup"
FN   = "verify_crew_scheduling_rep_setup"

FULL_RESULT = {
    "display_name_found": True,
    "home_airport_found": True,
    "base_airport_found": True,
    "personalization_found": True,
    "friend1_found": True,
    "friend2_found": True,
    "friend3_found": True,
    "settings_reachable": True,
    "friends_reachable": True,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:     score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: name + personalization = 20+20 = 40 < 60
r_partial = _run(TASK, FN, {
    "display_name_found": True, "home_airport_found": False, "base_airport_found": False,
    "personalization_found": True, "friend1_found": False, "friend2_found": False, "friend3_found": False,
})
print(f"Partial (name+pers): score={r_partial['score']}, passed={r_partial['passed']}")
assert r_partial['score'] == 40 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full
r_full = _run(TASK, FN, FULL_RESULT)
print(f"Full:           score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target
r_wt = _run(TASK, FN, {k: False for k in FULL_RESULT})
print(f"Wrong-target:   score={r_wt['score']}, passed={r_wt['passed']}")
assert r_wt['score'] == 0 and not r_wt['passed'], f"FAIL wrong-target: {r_wt}"

results_summary[TASK] = "PASS"
print(f"=> crew_scheduling_rep_setup: ALL TESTS PASSED")


# ===========================================================================
# Final summary
# ===========================================================================
print("\n" + "=" * 60)
print("FINAL SUMMARY")
print("=" * 60)
all_passed = all(v == "PASS" for v in results_summary.values())
for task, status in results_summary.items():
    print(f"  {task}: {status}")
print(f"\nAll tests passed: {all_passed}")
if not all_passed:
    sys.exit(1)
print("\nAll 5 new flica_env tasks passed pipeline verification!")
