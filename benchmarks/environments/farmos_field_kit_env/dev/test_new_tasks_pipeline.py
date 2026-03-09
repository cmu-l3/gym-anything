#!/usr/bin/env python3
"""
Pipeline verification tests for the 5 new farmos_field_kit_env tasks.

Tests each verifier with:
  1. Do-nothing  → copy_from_env raises (no XML on device) → expect score=0, passed=False
  2. Partial     → XML with 2 of 5 log names              → expect 0 < score < pass_threshold
  3. Full        → XML with all 5 log names               → expect score >= 80, passed=True
  4. Wrong-target → XML with logs from a different task   → expect score=0, passed=False

No Android VM required.  Uses a mock copy_from_env that writes crafted
Android UI dump XML to the destination file.
"""

import importlib.util
import json
import os
import sys
import time

TASKS_DIR    = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tasks")
EVIDENCE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_verifier(task_name):
    """Dynamically load a task's verifier.py module."""
    path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _copy_fn_from_xml(xml_text):
    """Return a copy_from_env callable that writes xml_text to the destination."""
    def copy_fn(src_path, dest_path):
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(xml_text)
    return copy_fn


def _copy_fn_raises():
    """Return a copy_from_env callable that always raises (simulates missing file)."""
    def copy_fn(src_path, dest_path):
        raise FileNotFoundError(f"No such file on device: {src_path}")
    return copy_fn


def _make_xml(log_names=()):
    """
    Build a minimal Android UI dump XML with one TextView node per log name,
    mimicking what uiautomator dump produces for a farmOS Field Kit log list.
    Also includes some typical farmOS UI chrome text that should NOT match
    any required log names.
    """
    chrome = [
        "Tasks", "Sync", "Settings", "farmOS Field Kit",
        "Activity", "Harvest", "Input", "Observation",
        "Done", "Pending",
    ]
    nodes = []
    # Add UI chrome — must not trigger false positives
    for c in chrome:
        nodes.append(
            f'  <node class="android.widget.TextView" text="{c}" '
            f'content-desc="" resource-id="" />'
        )
    # Add the actual log names
    for name in log_names:
        nodes.append(
            f'  <node class="android.widget.TextView" text="{name}" '
            f'content-desc="" resource-id="" />'
        )
    body = "\n".join(nodes)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<hierarchy rotation="0">\n'
        f'{body}\n'
        '</hierarchy>\n'
    )


def _run(task_name, fn_name, xml_text):
    """Run verifier function with provided XML.  Returns result dict."""
    mod = _load_verifier(task_name)
    fn  = getattr(mod, fn_name)
    task_json_path = os.path.join(TASKS_DIR, task_name, "task.json")
    with open(task_json_path) as f:
        task_info = json.load(f)

    if xml_text is None:
        env_info = {"copy_from_env": _copy_fn_raises()}
    else:
        env_info = {"copy_from_env": _copy_fn_from_xml(xml_text)}

    return fn(traj=[], env_info=env_info, task_info=task_info)


results_summary = {}

# ===========================================================================
# TASK 1: crop_spray_day_records
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 1: crop_spray_day_records")
print("=" * 60)

TASK = "crop_spray_day_records"
FN   = "check_crop_spray_day_records"

ALL_LOGS = [
    "Pre-spray boom calibration check",
    "Glyphosate application Field 3 North",
    "Azoxystrobin fungicide Field 3 South",
    "Post-spray drift assessment",
    "Sprayer rinse and storage",
]

# Do-nothing: no XML file on device
r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: only first 2 logs created (score=40, < threshold 80)
xml_partial = _make_xml(ALL_LOGS[:2])
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial (2/5): score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] == 40 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: all 5 logs created (score=100, passed=True)
xml_full = _make_xml(ALL_LOGS)
r_full = _run(TASK, FN, xml_full)
print(f"Full (5/5):   score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: logs from multi_field_harvest_records (totally different task)
xml_wrong = _make_xml([
    "Pre-harvest combine inspection",
    "Corn harvest West Field 185 bu",
    "Corn harvest South Field 172 bu",
    "Soybean harvest North Field 52 bu",
    "End-of-day combine service",
])
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "crop_spray_day_records@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        "Do-nothing=0 (FileNotFoundError). Partial 2/5 logs = 40 pts. "
        "Full 5/5 logs = 100 pts, passed=True. "
        "Wrong-target (harvest logs) = 0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 2: multi_field_harvest_records
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 2: multi_field_harvest_records")
print("=" * 60)

TASK = "multi_field_harvest_records"
FN   = "check_multi_field_harvest_records"

ALL_LOGS = [
    "Pre-harvest combine inspection",
    "Corn harvest West Field 185 bu",
    "Corn harvest South Field 172 bu",
    "Soybean harvest North Field 52 bu",
    "End-of-day combine service",
]

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: first 2 logs only (40 pts)
xml_partial = _make_xml(ALL_LOGS[:2])
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial (2/5): score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] == 40 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: all 5 logs (100 pts)
xml_full = _make_xml(ALL_LOGS)
r_full = _run(TASK, FN, xml_full)
print(f"Full (5/5):   score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: GAP compliance logs instead of harvest logs
xml_wrong = _make_xml([
    "Worker hygiene training sign-in",
    "Irrigation well water E.coli sampling",
    "Field harvest bin sanitation log",
    "Field border wildlife intrusion check",
    "GAP audit records daily review",
])
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "multi_field_harvest_records@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        "Do-nothing=0. Partial 2/5 (inspection+West corn) = 40 pts. "
        "Full 5/5 = 100 pts, passed=True. "
        "Wrong-target (GAP logs) = 0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 3: livestock_health_treatment_log
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 3: livestock_health_treatment_log")
print("=" * 60)

TASK = "livestock_health_treatment_log"
FN   = "check_livestock_health_treatment_log"

ALL_LOGS = [
    "Pen 12 BRD respiratory assessment",
    "Enrofloxacin BRD treatment 12 head",
    "Sick pen setup and animal movement",
    "48hr BRD treatment response check",
    "Non-responder vet exam and hold",
]

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: first 3 logs (60 pts — still below threshold 80)
xml_partial = _make_xml(ALL_LOGS[:3])
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial (3/5): score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] == 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: all 5 logs (100 pts)
xml_full = _make_xml(ALL_LOGS)
r_full = _run(TASK, FN, xml_full)
print(f"Full (5/5):   score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: spray day logs instead of livestock logs
xml_wrong = _make_xml([
    "Pre-spray boom calibration check",
    "Glyphosate application Field 3 North",
    "Azoxystrobin fungicide Field 3 South",
    "Post-spray drift assessment",
    "Sprayer rinse and storage",
])
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "livestock_health_treatment_log@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        "Do-nothing=0. Partial 3/5 logs (BRD assessment+treatment+sick pen) = 60 pts. "
        "Full 5/5 = 100 pts, passed=True. "
        "Wrong-target (spray logs) = 0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 4: spring_field_operations_log
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 4: spring_field_operations_log")
print("=" * 60)

TASK = "spring_field_operations_log"
FN   = "check_spring_field_operations_log"

ALL_LOGS = [
    "Winter rye cover crop burndown",
    "Grid soil sampling Field 5",
    "Corn planting Field 7 East 32500 population",
    "Corn planting Field 8 32500 population",
    "Field 7 East planting quality check",
]

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: first 2 logs (40 pts)
xml_partial = _make_xml(ALL_LOGS[:2])
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial (2/5): score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] == 40 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: all 5 logs (100 pts)
xml_full = _make_xml(ALL_LOGS)
r_full = _run(TASK, FN, xml_full)
print(f"Full (5/5):   score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: livestock logs instead of spring planting logs
xml_wrong = _make_xml([
    "Pen 12 BRD respiratory assessment",
    "Enrofloxacin BRD treatment 12 head",
    "Sick pen setup and animal movement",
    "48hr BRD treatment response check",
    "Non-responder vet exam and hold",
])
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "spring_field_operations_log@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        "Do-nothing=0. Partial 2/5 (cover crop burndown+soil sampling) = 40 pts. "
        "Full 5/5 = 100 pts, passed=True. "
        "Wrong-target (livestock logs) = 0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 5: gap_compliance_audit_records
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 5: gap_compliance_audit_records")
print("=" * 60)

TASK = "gap_compliance_audit_records"
FN   = "check_gap_compliance_audit_records"

ALL_LOGS = [
    "Worker hygiene training sign-in",
    "Irrigation well water E.coli sampling",
    "Field harvest bin sanitation log",
    "Field border wildlife intrusion check",
    "GAP audit records daily review",
]

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: first 2 logs (40 pts)
xml_partial = _make_xml(ALL_LOGS[:2])
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial (2/5): score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] == 40 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: all 5 logs (100 pts)
xml_full = _make_xml(ALL_LOGS)
r_full = _run(TASK, FN, xml_full)
print(f"Full (5/5):   score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: spring planting logs instead of GAP logs
xml_wrong = _make_xml([
    "Winter rye cover crop burndown",
    "Grid soil sampling Field 5",
    "Corn planting Field 7 East 32500 population",
    "Corn planting Field 8 32500 population",
    "Field 7 East planting quality check",
])
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

# Extra: test that standard farmOS UI chrome text does NOT trigger false positives
xml_chrome_only = _make_xml([])  # Only standard UI text, no log names
r_chrome = _run(TASK, FN, xml_chrome_only)
print(f"Chrome-only:  score={r_chrome['score']}, passed={r_chrome['passed']}  | {r_chrome['feedback']}")
assert r_chrome['score'] == 0 and not r_chrome['passed'], f"FAIL chrome-only false positive: {r_chrome}"

results_summary[TASK] = {
    "task_id": "gap_compliance_audit_records@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        "Do-nothing=0. Partial 2/5 (hygiene training+water sampling) = 40 pts. "
        "Full 5/5 = 100 pts, passed=True. "
        "Wrong-target (spring logs) = 0 pts. "
        "Chrome-only (UI text without log names) = 0 pts, no false positives."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# Save evidence JSON
# ===========================================================================
print("\n" + "=" * 60)
print("SAVING EVIDENCE")
print("=" * 60)

test_date = time.strftime("%Y-%m-%d")
for task_name, summary in results_summary.items():
    evidence = {
        "task": task_name,
        "task_id": summary["task_id"],
        "test_date": test_date,
        "methodology": (
            "Pipeline simulation: verifier.py loaded directly and called with a mock "
            "copy_from_env function that writes a crafted Android uiautomator dump XML "
            "to a temp file. Four scenarios tested per task: (1) do-nothing — raises "
            "FileNotFoundError → score=0, passed=False; (2) partial — 2-3 of 5 log "
            "names present in XML → partial score, passed=False; (3) full — all 5 log "
            "names present → score=100, passed=True; (4) wrong-target — log names from "
            "a different farmos task → score=0, passed=False. No Android VM required."
        ),
        "pipeline_results": {
            "do_nothing":   {"score": summary["do_nothing_score"],   "passed": summary["do_nothing_passed"]},
            "partial":      {"score": summary["partial_score"],      "passed": summary["partial_passed"]},
            "full":         {"score": summary["full_score"],         "passed": summary["full_passed"]},
            "wrong_target": {"score": summary["wrong_target_score"], "passed": summary["wrong_target_passed"]},
        },
        "notes": summary["notes"],
        "env": "farmos_field_kit_env",
        "env_base": "android-avd-34",
        "app": "org.farmos.app (farmOS Field Kit)",
        "verification_method": "uiautomator dump → /sdcard/ui_dump_<task>.xml → copy_from_env → XML text attribute parsing",
    }
    out = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    with open(out, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"  Saved: {out}")


print("\n" + "=" * 60)
print("ALL PIPELINE TESTS PASSED")
print("=" * 60)
for task, data in results_summary.items():
    print(
        f"  {task}:\n"
        f"    do_nothing={data['do_nothing_score']}/{data['do_nothing_passed']}  "
        f"partial={data['partial_score']}  "
        f"full={data['full_score']}/{data['full_passed']}  "
        f"wrong_target={data['wrong_target_score']}/{data['wrong_target_passed']}"
    )
