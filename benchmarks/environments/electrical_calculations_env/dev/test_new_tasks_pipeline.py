#!/usr/bin/env python3
"""
Pipeline verification tests for the 5 new electrical_calculations_env tasks.

Tests each verifier with:
  1. Do-nothing  → copy_from_env raises (no XML available) → expect score=0, passed=False
  2. Partial     → XML with some but not all results        → expect 0 < score < pass_threshold
  3. Full        → XML with all expected results            → expect score >= pass_threshold, passed=True
  4. Wrong-target → XML with plausible-but-incorrect values → expect passed=False

No Android VM required. Uses mock copy_from_env that writes crafted XML to dest file.
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
    """Return a copy_from_env that writes xml_text to the destination."""
    def copy_fn(src_path, dest_path):
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(xml_text)
    return copy_fn


def _copy_fn_raises():
    """Return a copy_from_env that always raises (simulates missing file)."""
    def copy_fn(src_path, dest_path):
        raise FileNotFoundError(f"No such file on device: {src_path}")
    return copy_fn


def _make_xml(values=(), keywords=()):
    """
    Build a minimal Android UI dump XML with:
      - One TextView node per value (as a string in 'text' attribute)
      - One node with all keywords joined in 'text' attribute
    """
    nodes = []
    for v in values:
        nodes.append(f'  <node class="android.widget.TextView" text="{v}" content-desc="" />')
    if keywords:
        kw_text = " ".join(keywords)
        nodes.append(f'  <node class="android.widget.TextView" text="{kw_text}" content-desc="" />')
    body = "\n".join(nodes)
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<hierarchy rotation="0">\n{body}\n</hierarchy>\n'


def _run(task_name, fn_name, xml_text):
    """Run verifier function with provided XML. Returns result dict."""
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
# TASK 1: three_phase_load_analysis
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 1: three_phase_load_analysis")
print("=" * 60)

TASK = "three_phase_load_analysis"
FN   = "verify_three_phase_load_analysis"

# Do-nothing: no XML available
r = _run(TASK, FN, None)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: only apparent power visible (missing reactive)
xml_partial = _make_xml(
    values=["16627", "400", "24"],
    keywords=["three phase apparent power"]
)
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] > 0 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: all expected results visible
xml_full = _make_xml(
    values=["9976", "13302", "16627", "400", "24", "0.80"],
    keywords=["three phase reactive apparent real power"]
)
r_full = _run(TASK, FN, xml_full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: wrong reactive power (forgot to multiply by sin(arccos(PF)))
xml_wrong = _make_xml(
    values=["13302", "16627", "400", "24"],   # reactive missing
    keywords=["three phase power"]
)
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert not r_wrong['passed'], f"FAIL wrong-target should not pass: {r_wrong}"

results_summary[TASK] = {
    "task_id": "three_phase_load_analysis@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": "Do-nothing=0 (no XML). Full: 9976VAR + 13302W + 16627VA + 3-phase keywords + 400V/24A inputs."
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 2: single_phase_power_quality_audit
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 2: single_phase_power_quality_audit")
print("=" * 60)

TASK = "single_phase_power_quality_audit"
FN   = "verify_single_phase_power_quality_audit"

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: only apparent power + inputs visible (missing reactive power)
xml_partial = _make_xml(
    values=["6440", "230", "28"],
    keywords=["single phase apparent power"]
)
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] > 0 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: all expected results (PF=0.65: S=6440VA, P=4186W, Q=4894VAR)
xml_full = _make_xml(
    values=["4894", "4186", "6440", "230", "28", "0.65"],
    keywords=["single phase reactive apparent real power factor"]
)
r_full = _run(TASK, FN, xml_full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: agent used Ohm's Law calculator instead (R=230/28=8.21Ω)
# This shows R=8.21Ω but NOT any power values → reactive power check fails
xml_wrong = _make_xml(
    values=["8.21", "230", "28"],
    keywords=["ohms law resistance voltage current"]
)
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert not r_wrong['passed'], f"FAIL wrong-target should not pass: {r_wrong}"

results_summary[TASK] = {
    "task_id": "single_phase_power_quality_audit@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": "Do-nothing=0. Full: 4894VAR + 4186W + 6440VA + single-phase keywords + 230V/28A (PF=0.65)."
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 3: motor_cable_sizing_calculation
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 3: motor_cable_sizing_calculation")
print("=" * 60)

TASK = "motor_cable_sizing_calculation"
FN   = "verify_motor_cable_sizing_calculation"

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: correct current but no cable size result
xml_partial = _make_xml(
    values=["20.61", "240", "35", "0.85"],
    keywords=["current motor power"]
)
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] > 0, f"FAIL partial: {r_partial}"

# Full: correct current + cable keywords + cable size + parameters
xml_full = _make_xml(
    values=["20.61", "240", "35", "0.85", "4.0"],
    keywords=["cable size mm2 voltage drop conductor"]
)
r_full = _run(TASK, FN, xml_full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: wrong current (missing efficiency - 18.14A) + cable
xml_wrong = _make_xml(
    values=["18.14", "240", "35", "0.85", "2.5"],
    keywords=["cable size mm2 voltage drop"]
)
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert not r_wrong['passed'], f"FAIL wrong-target should not pass: {r_wrong}"

results_summary[TASK] = {
    "task_id": "motor_cable_sizing_calculation@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": "Do-nothing=0. Full: 20.61A current (eff+PF applied) + cable size 4.0mm² + keywords."
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 4: delta_wye_resistor_network
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 4: delta_wye_resistor_network")
print("=" * 60)

TASK = "delta_wye_resistor_network"
FN   = "verify_delta_wye_resistor_network"

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: wye values visible but no parallel result
xml_partial = _make_xml(
    values=["45", "15", "22.5", "90", "135"],
    keywords=["delta wye conversion star"]
)
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] > 0 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: parallel result + all wye values + delta keywords + inputs
xml_full = _make_xml(
    values=["9", "45", "15", "22.5", "90", "135"],
    keywords=["delta wye conversion star resistance"]
)
r_full = _run(TASK, FN, xml_full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: only delta input values, wrong wye conversion
xml_wrong = _make_xml(
    values=["90", "45", "135", "30", "10", "7.5"],  # wrong wye values
    keywords=["delta wye conversion"]
)
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert not r_wrong['passed'], f"FAIL wrong-target should not pass: {r_wrong}"

results_summary[TASK] = {
    "task_id": "delta_wye_resistor_network@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": "Do-nothing=0. Full: 9Ω parallel + R_A=45 + R_B=15 + R_C=22.5 + delta keywords + 90/45/135 inputs."
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 5: three_phase_line_phase_conversions
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 5: three_phase_line_phase_conversions")
print("=" * 60)

TASK = "three_phase_line_phase_conversions"
FN   = "verify_three_phase_line_phase_conversions"

# Do-nothing
r = _run(TASK, FN, None)
print(f"Do-nothing:  score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

# Partial: only phase voltage visible (missing delta phase current)
# Use compound phrases that match the keyword check (line voltage, phase voltage)
xml_partial = _make_xml(
    values=["239.6", "415", "63"],
    keywords=["line voltage phase voltage line to phase"]
)
r_partial = _run(TASK, FN, xml_partial)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] > 0 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full: both conversion results visible with specific compound phrase keywords
xml_full = _make_xml(
    values=["36.37", "239.6", "415", "63"],
    keywords=["line to phase line current phase current line voltage phase voltage"]
)
r_full = _run(TASK, FN, xml_full)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

# Wrong-target: agent only computed wye phase voltage, not delta phase current
xml_wrong = _make_xml(
    values=["239.6", "415"],          # no current result visible
    keywords=["line voltage phase voltage line to phase"]
)
r_wrong = _run(TASK, FN, xml_wrong)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert not r_wrong['passed'], f"FAIL wrong-target should not pass: {r_wrong}"

results_summary[TASK] = {
    "task_id": "three_phase_line_phase_conversions@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": "Do-nothing=0. Full: 36.37A delta phase current + 239.6V wye phase voltage + compound phrase keywords."
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
        "test_date": test_date,
        "methodology": (
            "Pipeline simulation: verifier.py run with mock copy_from_env that writes "
            "crafted Android UI dump XML to a temp file. Simulates no-XML (do-nothing), "
            "partial results, full results, and wrong-target scenarios."
        ),
        "pipeline_results": {
            "do_nothing":  {"score": summary["do_nothing_score"],  "passed": summary["do_nothing_passed"]},
            "partial":     {"score": summary["partial_score"]},
            "full":        {"score": summary["full_score"],        "passed": summary["full_passed"]},
            "wrong_target":{"score": summary["wrong_target_score"],"passed": summary["wrong_target_passed"]},
        },
        "notes": summary["notes"]
    }
    out = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    with open(out, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"  Saved: {out}")

print("\n" + "=" * 60)
print("ALL PIPELINE TESTS PASSED")
print("=" * 60)
for task, data in results_summary.items():
    print(f"  {task}: do_nothing=0/False  partial={data['partial_score']}  full={data['full_score']}/pass={data['full_passed']}")
