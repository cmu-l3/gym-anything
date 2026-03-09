#!/usr/bin/env python3
"""
Pipeline verification tests for the 5 new fiji_env tasks.

Tests each verifier with:
  1. Do-nothing  → copy_from_env raises FileNotFoundError → expect score=0, passed=False
  2. Partial     → JSON with some criteria met, total < 60 pts → expect passed=False
  3. Full        → JSON with all criteria met, total = 100 pts → expect score>=60, passed=True
  4. Baseline    → All-zeros/False JSON (baseline from setup_task.sh) → expect score=0

No VM required.  Uses a mock copy_from_env that writes crafted JSON to the destination.
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


def _copy_fn_raises():
    """Return a copy_from_env callable that always raises (simulates missing file)."""
    def copy_fn(src_path, dest_path):
        raise FileNotFoundError(f"No such file on environment: {src_path}")
    return copy_fn


def _copy_fn_from_json(data):
    """Return a copy_from_env callable that writes JSON data to the destination."""
    def copy_fn(src_path, dest_path):
        with open(dest_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
    return copy_fn


def _run(task_name, fn_name, json_data_or_none):
    """Run verifier function. If json_data_or_none is None, copy_from_env raises."""
    mod = _load_verifier(task_name)
    fn  = getattr(mod, fn_name)
    task_json_path = os.path.join(TASKS_DIR, task_name, "task.json")
    with open(task_json_path) as f:
        task_info = json.load(f)

    if json_data_or_none is None:
        env_info = {"copy_from_env": _copy_fn_raises()}
    else:
        env_info = {"copy_from_env": _copy_fn_from_json(json_data_or_none)}

    return fn(traj=[], env_info=env_info, task_info=task_info)


results_summary = {}


# ===========================================================================
# TASK 1: fluorescence_colocalization_analysis
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 1: fluorescence_colocalization_analysis")
print("=" * 60)

TASK = "fluorescence_colocalization_analysis"
FN   = "verify_fluorescence_colocalization_analysis"

# Baseline JSON: written by setup_task.sh before any agent work
BASELINE_JSON_1 = {
    "task_start": 0,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "n_images_analyzed": 0,
    "has_required_columns": False,
    "pearson_values": [],
    "pearson_all_valid": False,
    "manders_m1_values": [],
    "manders_m2_values": [],
    "m1_all_valid": False,
    "m2_all_valid": False,
    "viz_exists": False,
    "viz_modified_after_start": False,
    "viz_size_bytes": 0,
}

# Partial: csv created+required columns+3 images+pearson valid, no manders, no viz
# 15+15+10+20+0+0 = 60  — wait, need to be < 60
# Use 3 images (10pts partial) + no pearson_values (empty) = 15+15+10 = 40 pts
PARTIAL_JSON_1 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "n_images_analyzed": 3,
    "has_required_columns": True,
    "pearson_values": [],        # No Pearson values despite columns existing
    "pearson_all_valid": False,
    "manders_m1_values": [],
    "manders_m2_values": [],
    "m1_all_valid": False,
    "m2_all_valid": False,
    "viz_exists": False,
    "viz_modified_after_start": False,
    "viz_size_bytes": 0,
}
# Expected: 15+15+10 = 40 pts, passed=False

# Full: all criteria met
FULL_JSON_1 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "n_images_analyzed": 6,
    "has_required_columns": True,
    "pearson_values": [0.72, 0.68, 0.81, 0.75, 0.69, 0.77],
    "pearson_all_valid": True,
    "manders_m1_values": [0.88, 0.91, 0.85, 0.89, 0.87, 0.90],
    "manders_m2_values": [0.76, 0.79, 0.74, 0.78, 0.80, 0.75],
    "m1_all_valid": True,
    "m2_all_valid": True,
    "viz_exists": True,
    "viz_modified_after_start": True,
    "viz_size_bytes": 45000,
}
# Expected: 15+15+20+20+20+10 = 100 pts, passed=True

# Do-nothing: raises
r_do_nothing = _run(TASK, FN, None)
print(f"Do-nothing:  score={r_do_nothing['score']}, passed={r_do_nothing['passed']}  | {r_do_nothing.get('feedback','')[:80]}")
assert r_do_nothing['score'] == 0 and not r_do_nothing['passed'], f"FAIL do-nothing: {r_do_nothing}"

# Baseline: all-zeros JSON from setup
r_baseline = _run(TASK, FN, BASELINE_JSON_1)
print(f"Baseline:    score={r_baseline['score']}, passed={r_baseline['passed']}  | {r_baseline.get('feedback','')[:80]}")
assert r_baseline['score'] == 0 and not r_baseline['passed'], f"FAIL baseline: {r_baseline}"

# Partial
r_partial = _run(TASK, FN, PARTIAL_JSON_1)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial.get('feedback','')[:80]}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"

# Full
r_full = _run(TASK, FN, FULL_JSON_1)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full.get('feedback','')[:80]}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

print(f"PASS: do_nothing=0, baseline=0, partial={r_partial['score']}, full={r_full['score']}/100")

results_summary[TASK] = {
    "task_id": "fluorescence_colocalization_analysis@1",
    "do_nothing_score": r_do_nothing['score'], "do_nothing_passed": r_do_nothing['passed'],
    "baseline_score": r_baseline['score'], "baseline_passed": r_baseline['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "notes": (
        "Do-nothing=0 (FileNotFoundError). Baseline=0 (all-false JSON). "
        f"Partial (3 images, no Pearson/Manders/viz) = {r_partial['score']} pts < 60. "
        f"Full (6 images, valid Pearson R + M1+M2 + viz) = {r_full['score']} pts, passed=True."
    ),
}


# ===========================================================================
# TASK 2: fluorescent_microsphere_calibration
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 2: fluorescent_microsphere_calibration")
print("=" * 60)

TASK = "fluorescent_microsphere_calibration"
FN   = "verify_fluorescent_microsphere_calibration"

BASELINE_JSON_2 = {
    "task_start": 0,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "has_required_columns": False,
    "n_particles": 0,
    "diameter_values": [],
    "diameters_positive": False,
    "mean_diameter_um": None,
    "cv_percent": None,
    "summary_exists": False,
    "summary_modified_after_start": False,
    "summary_has_cv_info": False,
    "summary_has_n_particles": False,
    "summary_has_mean_diameter": False,
    "summary_size_bytes": 0,
}

# Partial: csv+cols created, 7 particles (partial), no diameters, no summary
# 15+15+10+0+0+0 = 40 pts
PARTIAL_JSON_2 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "has_required_columns": True,
    "n_particles": 7,
    "diameter_values": [],        # No diameter column parsed
    "diameters_positive": False,
    "mean_diameter_um": None,
    "cv_percent": None,
    "summary_exists": False,
    "summary_modified_after_start": False,
    "summary_has_cv_info": False,
    "summary_has_n_particles": False,
    "summary_has_mean_diameter": False,
    "summary_size_bytes": 0,
}
# Expected: 15+15+10 = 40 pts

# Full: all criteria met
FULL_JSON_2 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "has_required_columns": True,
    "n_particles": 28,
    "diameter_values": [1.91, 2.05, 1.98, 2.12, 1.87, 2.03, 1.94, 2.08, 1.99, 2.01,
                        1.96, 2.07, 1.93, 2.11, 1.88, 2.04, 1.97, 2.06, 1.92, 2.09,
                        2.00, 1.95, 2.03, 1.90, 2.02, 1.96, 2.04, 1.99],
    "diameters_positive": True,
    "mean_diameter_um": 1.99,
    "cv_percent": 4.8,   # Well below 40% threshold
    "summary_exists": True,
    "summary_modified_after_start": True,
    "summary_has_cv_info": True,
    "summary_has_n_particles": True,
    "summary_has_mean_diameter": True,
    "summary_size_bytes": 512,
}
# Expected: 15+15+20+15+20+15 = 100 pts

r_do_nothing = _run(TASK, FN, None)
print(f"Do-nothing:  score={r_do_nothing['score']}, passed={r_do_nothing['passed']}  | {r_do_nothing.get('feedback','')[:80]}")
assert r_do_nothing['score'] == 0 and not r_do_nothing['passed'], f"FAIL do-nothing: {r_do_nothing}"

r_baseline = _run(TASK, FN, BASELINE_JSON_2)
print(f"Baseline:    score={r_baseline['score']}, passed={r_baseline['passed']}  | {r_baseline.get('feedback','')[:80]}")
assert r_baseline['score'] == 0 and not r_baseline['passed'], f"FAIL baseline: {r_baseline}"

r_partial = _run(TASK, FN, PARTIAL_JSON_2)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial.get('feedback','')[:80]}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"

r_full = _run(TASK, FN, FULL_JSON_2)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full.get('feedback','')[:80]}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

print(f"PASS: do_nothing=0, baseline=0, partial={r_partial['score']}, full={r_full['score']}/100")

results_summary[TASK] = {
    "task_id": "fluorescent_microsphere_calibration@1",
    "do_nothing_score": r_do_nothing['score'], "do_nothing_passed": r_do_nothing['passed'],
    "baseline_score": r_baseline['score'], "baseline_passed": r_baseline['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "notes": (
        "Do-nothing=0 (FileNotFoundError). Baseline=0 (all-false JSON). "
        f"Partial (7 particles, no diameters/summary) = {r_partial['score']} pts < 60. "
        f"Full (28 particles, CV%=4.8, all criteria met) = {r_full['score']} pts, passed=True."
    ),
}


# ===========================================================================
# TASK 3: cell_nuclear_morphometry_batch
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 3: cell_nuclear_morphometry_batch")
print("=" * 60)

TASK = "cell_nuclear_morphometry_batch"
FN   = "verify_cell_nuclear_morphometry_batch"

BASELINE_JSON_3 = {
    "task_start": 0,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "total_nuclei": 0,
    "n_images_processed": 0,
    "has_required_columns": False,
    "circularity_all_valid": False,
    "solidity_all_valid": False,
    "area_all_positive": False,
    "summary_exists": False,
    "summary_modified_after_start": False,
    "summary_has_qc_flags": False,
    "summary_size_bytes": 0,
    "overlay_exists": False,
    "overlay_modified_after_start": False,
    "overlay_size_bytes": 0,
}

# Partial: csv+cols+30 nuclei (partial 10pts)+circularity+solidity valid (15pts)
# No area, no summary, no overlay
# 15+15+10+15+0+0+0 = 55 pts < 60
PARTIAL_JSON_3 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "total_nuclei": 30,
    "n_images_processed": 4,
    "has_required_columns": True,
    "circularity_all_valid": True,
    "circularity_min": 0.52,
    "circularity_max": 0.94,
    "solidity_all_valid": True,
    "solidity_min": 0.78,
    "solidity_max": 0.98,
    "area_all_positive": False,
    "area_min": -1.0,
    "summary_exists": False,
    "summary_modified_after_start": False,
    "summary_has_qc_flags": False,
    "summary_size_bytes": 0,
    "summary_line_count": 0,
    "overlay_exists": False,
    "overlay_modified_after_start": False,
    "overlay_size_bytes": 0,
}
# Expected: 15+15+10+15+0+0+0 = 55 pts < 60

# Full: all criteria met
FULL_JSON_3 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "total_nuclei": 82,
    "n_images_processed": 7,
    "has_required_columns": True,
    "circularity_all_valid": True,
    "circularity_min": 0.48,
    "circularity_max": 0.96,
    "solidity_all_valid": True,
    "solidity_min": 0.75,
    "solidity_max": 0.99,
    "area_all_positive": True,
    "area_min": 85.3,
    "summary_exists": True,
    "summary_modified_after_start": True,
    "summary_has_qc_flags": True,
    "summary_size_bytes": 1024,
    "summary_line_count": 10,
    "overlay_exists": True,
    "overlay_modified_after_start": True,
    "overlay_size_bytes": 25000,
}
# Expected: 15+15+20+15+10+15+10 = 100 pts

r_do_nothing = _run(TASK, FN, None)
print(f"Do-nothing:  score={r_do_nothing['score']}, passed={r_do_nothing['passed']}  | {r_do_nothing.get('feedback','')[:80]}")
assert r_do_nothing['score'] == 0 and not r_do_nothing['passed'], f"FAIL do-nothing: {r_do_nothing}"

r_baseline = _run(TASK, FN, BASELINE_JSON_3)
print(f"Baseline:    score={r_baseline['score']}, passed={r_baseline['passed']}  | {r_baseline.get('feedback','')[:80]}")
assert r_baseline['score'] == 0 and not r_baseline['passed'], f"FAIL baseline: {r_baseline}"

r_partial = _run(TASK, FN, PARTIAL_JSON_3)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial.get('feedback','')[:80]}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"

r_full = _run(TASK, FN, FULL_JSON_3)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full.get('feedback','')[:80]}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

print(f"PASS: do_nothing=0, baseline=0, partial={r_partial['score']}, full={r_full['score']}/100")

results_summary[TASK] = {
    "task_id": "cell_nuclear_morphometry_batch@1",
    "do_nothing_score": r_do_nothing['score'], "do_nothing_passed": r_do_nothing['passed'],
    "baseline_score": r_baseline['score'], "baseline_passed": r_baseline['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "notes": (
        "Do-nothing=0 (FileNotFoundError). Baseline=0 (all-false JSON). "
        f"Partial (30 nuclei, no area/summary/overlay) = {r_partial['score']} pts < 60. "
        f"Full (82 nuclei, all morphometry+summary+overlay) = {r_full['score']} pts, passed=True."
    ),
}


# ===========================================================================
# TASK 4: 3d_brain_structure_volumetry
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 4: 3d_brain_structure_volumetry")
print("=" * 60)

TASK = "3d_brain_structure_volumetry"
FN   = "verify_3d_brain_structure_volumetry"

BASELINE_JSON_4 = {
    "task_start": 0,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "n_structures": 0,
    "has_required_columns": False,
    "volumes_mm3": {},
    "all_volumes_positive": False,
    "brain_volume_mm3": 0.0,
    "ventricle_volume_mm3": 0.0,
    "ortho_exists": False,
    "ortho_modified_after_start": False,
    "ortho_size_bytes": 0,
    "report_exists": False,
    "report_modified_after_start": False,
    "report_size_bytes": 0,
    "report_has_brain_keyword": False,
    "report_has_ventricle_keyword": False,
    "report_has_volume_keyword": False,
    "report_line_count": 0,
    "header_cols": [],
}

# Partial: csv+cols+1 structure (7pts partial)+all_positive+brain_volume=50 (3pts too small)
# No ortho, no report
# 15+15+7+15+3+0+0 = 55 pts < 60
PARTIAL_JSON_4 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "n_structures": 1,
    "has_required_columns": True,
    "header_cols": ["structure_name", "volume_mm3"],
    "volumes_mm3": {"brain_tissue": 50.0},
    "all_volumes_positive": True,
    "brain_volume_mm3": 50.0,     # <= 100, too small → 3 pts only
    "ventricle_volume_mm3": 0.0,
    "ortho_exists": False,
    "ortho_modified_after_start": False,
    "ortho_size_bytes": 0,
    "report_exists": False,
    "report_modified_after_start": False,
    "report_size_bytes": 0,
    "report_has_brain_keyword": False,
    "report_has_ventricle_keyword": False,
    "report_has_volume_keyword": False,
    "report_line_count": 0,
}
# Expected: 15+15+7+15+3+0+0 = 55 pts

# Full: all criteria met
FULL_JSON_4 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "n_structures": 2,
    "has_required_columns": True,
    "header_cols": ["structure_name", "volume_mm3", "voxel_count"],
    "volumes_mm3": {"brain_tissue": 850.0, "ventricles": 18.5},
    "all_volumes_positive": True,
    "brain_volume_mm3": 850.0,    # > 100 and < 10M → plausible
    "ventricle_volume_mm3": 18.5,
    "ortho_exists": True,
    "ortho_modified_after_start": True,
    "ortho_size_bytes": 48000,    # > 10 KB
    "report_exists": True,
    "report_modified_after_start": True,
    "report_size_bytes": 512,
    "report_has_brain_keyword": True,
    "report_has_ventricle_keyword": True,
    "report_has_volume_keyword": True,
    "report_line_count": 15,
}
# Expected: 15+15+15+15+15+15+10 = 100 pts

r_do_nothing = _run(TASK, FN, None)
print(f"Do-nothing:  score={r_do_nothing['score']}, passed={r_do_nothing['passed']}  | {r_do_nothing.get('feedback','')[:80]}")
assert r_do_nothing['score'] == 0 and not r_do_nothing['passed'], f"FAIL do-nothing: {r_do_nothing}"

r_baseline = _run(TASK, FN, BASELINE_JSON_4)
print(f"Baseline:    score={r_baseline['score']}, passed={r_baseline['passed']}  | {r_baseline.get('feedback','')[:80]}")
assert r_baseline['score'] == 0 and not r_baseline['passed'], f"FAIL baseline: {r_baseline}"

r_partial = _run(TASK, FN, PARTIAL_JSON_4)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial.get('feedback','')[:80]}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"

r_full = _run(TASK, FN, FULL_JSON_4)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full.get('feedback','')[:80]}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

print(f"PASS: do_nothing=0, baseline=0, partial={r_partial['score']}, full={r_full['score']}/100")

results_summary[TASK] = {
    "task_id": "3d_brain_structure_volumetry@1",
    "do_nothing_score": r_do_nothing['score'], "do_nothing_passed": r_do_nothing['passed'],
    "baseline_score": r_baseline['score'], "baseline_passed": r_baseline['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "notes": (
        "Do-nothing=0 (FileNotFoundError). Baseline=0 (all-false JSON). "
        f"Partial (1 structure, brain=50mm3 too small, no ortho/report) = {r_partial['score']} pts < 60. "
        f"Full (2 structures: brain+ventricles, ortho+report) = {r_full['score']} pts, passed=True."
    ),
}


# ===========================================================================
# TASK 5: gel_electrophoresis_densitometry
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 5: gel_electrophoresis_densitometry")
print("=" * 60)

TASK = "gel_electrophoresis_densitometry"
FN   = "verify_gel_electrophoresis_densitometry"

BASELINE_JSON_5 = {
    "task_start": 0,
    "csv_exists": False,
    "csv_modified_after_start": False,
    "has_required_columns": False,
    "n_lanes": 0,
    "raw_intensities": [],
    "raw_intensities_positive": False,
    "normalized_intensities": [],
    "normalized_has_variation": False,
    "lane1_normalized_near_one": False,
    "profiles_exists": False,
    "profiles_modified_after_start": False,
    "profiles_size_bytes": 0,
    "report_exists": False,
    "report_modified_after_start": False,
    "report_size_bytes": 0,
    "report_has_lane_keyword": False,
    "report_has_intensity_keyword": False,
}

# Partial: csv+cols+2 lanes (10pts)+raw positive (15pts), no profiles/report
# n_lanes=2 → variation check runs but normalized empty → 0
# 15+15+10+15+0+0+0 = 55 pts < 60
PARTIAL_JSON_5 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "has_required_columns": True,
    "n_lanes": 2,
    "raw_intensities": [52341.0, 38420.0],
    "raw_intensities_positive": True,
    "normalized_intensities": [],  # not computed
    "normalized_has_variation": False,
    "lane1_normalized_near_one": False,
    "profiles_exists": False,
    "profiles_modified_after_start": False,
    "profiles_size_bytes": 0,
    "report_exists": False,
    "report_modified_after_start": False,
    "report_size_bytes": 0,
    "report_has_lane_keyword": False,
    "report_has_intensity_keyword": False,
}
# Expected: 15+15+10+15+0+0+0 = 55 pts < 60

# Full: all criteria met
FULL_JSON_5 = {
    "task_start": 1000000,
    "csv_exists": True,
    "csv_modified_after_start": True,
    "has_required_columns": True,
    "n_lanes": 5,
    "raw_intensities": [52341.0, 38420.0, 61234.0, 45678.0, 29100.0],
    "raw_intensities_positive": True,
    "normalized_intensities": [1.0, 0.734, 1.170, 0.872, 0.556],
    "normalized_has_variation": True,  # max-min = 0.614 > 0.05
    "lane1_normalized_near_one": True,
    "profiles_exists": True,
    "profiles_modified_after_start": True,
    "profiles_size_bytes": 18000,
    "report_exists": True,
    "report_modified_after_start": True,
    "report_size_bytes": 756,
    "report_has_lane_keyword": True,
    "report_has_intensity_keyword": True,
}
# Expected: 15+15+20+15+15+10+10 = 100 pts

r_do_nothing = _run(TASK, FN, None)
print(f"Do-nothing:  score={r_do_nothing['score']}, passed={r_do_nothing['passed']}  | {r_do_nothing.get('feedback','')[:80]}")
assert r_do_nothing['score'] == 0 and not r_do_nothing['passed'], f"FAIL do-nothing: {r_do_nothing}"

r_baseline = _run(TASK, FN, BASELINE_JSON_5)
print(f"Baseline:    score={r_baseline['score']}, passed={r_baseline['passed']}  | {r_baseline.get('feedback','')[:80]}")
assert r_baseline['score'] == 0 and not r_baseline['passed'], f"FAIL baseline: {r_baseline}"

r_partial = _run(TASK, FN, PARTIAL_JSON_5)
print(f"Partial:     score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial.get('feedback','')[:80]}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"

r_full = _run(TASK, FN, FULL_JSON_5)
print(f"Full:        score={r_full['score']}, passed={r_full['passed']}  | {r_full.get('feedback','')[:80]}")
assert r_full['score'] >= 60 and r_full['passed'], f"FAIL full: {r_full}"

print(f"PASS: do_nothing=0, baseline=0, partial={r_partial['score']}, full={r_full['score']}/100")

results_summary[TASK] = {
    "task_id": "gel_electrophoresis_densitometry@1",
    "do_nothing_score": r_do_nothing['score'], "do_nothing_passed": r_do_nothing['passed'],
    "baseline_score": r_baseline['score'], "baseline_passed": r_baseline['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "notes": (
        "Do-nothing=0 (FileNotFoundError). Baseline=0 (all-false JSON). "
        f"Partial (2 lanes, raw+, no normalized/profiles/report) = {r_partial['score']} pts < 60. "
        f"Full (5 lanes, normalized variation, profiles+report) = {r_full['score']} pts, passed=True."
    ),
}


# ===========================================================================
# Save evidence JSONs
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
            "copy_from_env function that writes crafted JSON to a temp file. "
            "Four scenarios tested per task: "
            "(1) do-nothing — raises FileNotFoundError → score=0, passed=False; "
            "(2) baseline — all-zeros/False JSON from setup_task.sh → score=0, passed=False; "
            "(3) partial — JSON with partial completion (some criteria met, total < 60) → passed=False; "
            "(4) full — JSON with all criteria met → score>=60, passed=True. "
            "No Fiji/ImageJ VM required."
        ),
        "pipeline_results": {
            "do_nothing":  {"score": summary["do_nothing_score"],  "passed": summary["do_nothing_passed"]},
            "baseline":    {"score": summary["baseline_score"],    "passed": summary["baseline_passed"]},
            "partial":     {"score": summary["partial_score"],     "passed": summary["partial_passed"]},
            "full":        {"score": summary["full_score"],        "passed": summary["full_passed"]},
        },
        "notes": summary["notes"],
        "env": "fiji_env",
        "env_base": "ubuntu-gnome-systemd_highres",
        "app": "Fiji (Fiji Is Just ImageJ) scientific image analysis",
        "verification_method": (
            "export_result.sh writes /tmp/<task>_result.json → "
            "copy_from_env → verifier.py reads JSON and applies scoring criteria"
        ),
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
        f"baseline={data['baseline_score']}  "
        f"partial={data['partial_score']}  "
        f"full={data['full_score']}/{data['full_passed']}"
    )
