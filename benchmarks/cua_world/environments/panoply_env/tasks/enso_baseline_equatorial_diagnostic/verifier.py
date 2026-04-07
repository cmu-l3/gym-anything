#!/usr/bin/env python3
"""
Verifier for enso_baseline_equatorial_diagnostic task.

Occupation: Climate Services Analyst
Industry: Seasonal Climate Forecasting
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 70):
  1. Spatial SST map exported (20 pts)
  2. Equatorial line plot exported (20 pts)
  3. Report contains all required fields (20 pts)
  4. SST values physically plausible (20 pts)
  5. ENSO_PHASE = NEUTRAL (20 pts)
"""

import json
import os
import re
import tempfile


def extract_float(string_val):
    """Extracts the first floating point number from a string."""
    match = re.search(r"[-+]?\d*\.\d+|\d+", str(string_val))
    if match:
        return float(match.group(0))
    return None


def verify_enso_baseline_equatorial_diagnostic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/enso_baseline_equatorial_diagnostic_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Spatial Map exported (20 pts)
    # ----------------------------------------------------------------
    map_exists = result.get('spatial_map_exists', False)
    map_mtime = int(result.get('spatial_map_mtime', 0))
    map_size = int(result.get('spatial_map_size', 0))

    if map_exists and map_mtime >= task_start and map_size >= 15000:
        score += 20
        feedback.append(f"Spatial SST map exported ({map_size} bytes)")
    elif map_exists and map_mtime >= task_start and map_size >= 5000:
        score += 10
        feedback.append(f"Spatial SST map present but small ({map_size} bytes)")
    else:
        feedback.append(f"Spatial SST map missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 2: Equatorial Line Plot exported (20 pts)
    # ----------------------------------------------------------------
    line_exists = result.get('line_plot_exists', False)
    line_mtime = int(result.get('line_plot_mtime', 0))
    line_size = int(result.get('line_plot_size', 0))

    if line_exists and line_mtime >= task_start and line_size >= 8000:
        score += 20
        feedback.append(f"Equatorial line plot exported ({line_size} bytes)")
    elif line_exists and line_mtime >= task_start and line_size >= 3000:
        score += 10
        feedback.append(f"Line plot present but small ({line_size} bytes)")
    else:
        feedback.append(f"Equatorial line plot missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 3: Report fields (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))

    warm_pool_raw = result.get('warm_pool_sst', '').strip()
    cold_tongue_raw = result.get('cold_tongue_sst', '').strip()
    gradient_raw = result.get('sst_gradient', '').strip()
    nino34_raw = result.get('nino34_sst', '').strip()
    enso_phase = result.get('enso_phase', '').strip()
    plot_type = result.get('plot_type_used', '').strip()

    fields_present = sum([
        bool(warm_pool_raw),
        bool(cold_tongue_raw),
        bool(gradient_raw),
        bool(nino34_raw),
        bool(enso_phase),
        bool(plot_type)
    ])

    if report_exists and report_mtime >= task_start:
        if fields_present == 6:
            score += 20
            feedback.append("Report complete with all 6 required fields")
        elif fields_present >= 3:
            score += 10
            feedback.append(f"Report partial ({fields_present}/6 fields)")
        else:
            feedback.append("Report largely empty")
    else:
        feedback.append("Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 4: Plausible values (20 pts)
    # ----------------------------------------------------------------
    warm_pool_val = extract_float(warm_pool_raw)
    cold_tongue_val = extract_float(cold_tongue_raw)
    gradient_val = extract_float(gradient_raw)
    nino34_val = extract_float(nino34_raw)

    plausible_count = 0
    if warm_pool_val is not None and 28.0 <= warm_pool_val <= 31.0:
        plausible_count += 1
    if cold_tongue_val is not None and 20.0 <= cold_tongue_val <= 26.0:
        plausible_count += 1
    if gradient_val is not None and 3.0 <= gradient_val <= 10.0:
        plausible_count += 1
    if nino34_val is not None and 25.0 <= nino34_val <= 28.5:
        plausible_count += 1

    if plausible_count == 4:
        score += 20
        feedback.append("All SST values are physically plausible for July climatology")
    elif plausible_count > 0:
        score += (plausible_count * 5)
        feedback.append(f"{plausible_count}/4 SST values are physically plausible")
    else:
        feedback.append("No extracted SST values were physically plausible (or none reported)")

    # ----------------------------------------------------------------
    # Criterion 5: ENSO phase correct (20 pts)
    # ----------------------------------------------------------------
    if enso_phase.upper() == "NEUTRAL":
        score += 20
        feedback.append("ENSO phase correctly classified as NEUTRAL (climatology base)")
    elif "NEUTRAL" in enso_phase.upper():
        score += 20
        feedback.append("ENSO phase contains NEUTRAL")
    elif enso_phase:
        feedback.append(f"ENSO phase incorrect (expected NEUTRAL, got '{enso_phase}')")

    # Confirm plot type intent
    if "line" in plot_type.lower() or "profile" in plot_type.lower() or "1d" in plot_type.lower() or "x axis" in plot_type.lower():
        feedback.append("Agent correctly reported using a line/profile plot")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }