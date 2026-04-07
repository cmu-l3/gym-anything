#!/usr/bin/env python3
"""
Verifier for tibetan_plateau_hypoxia_physiology task.

Occupation: Environmental Physiologist / High-Altitude Medical Researcher
Industry: Medical Research / Epidemiology
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Plot Export (20 pts): asia_surface_pressure_july.png exists,
     was created after task start, and has size >= 15KB.
  2. Report Formatting (20 pts): site_selection_report.txt exists,
     was created after task start, and contains all 4 required keys.
  3. Variable Selection Accuracy (30 pts): DATASET_VARIABLE_USED is 'pres'
     (or strongly indicates surface pressure). If 'slp' or sea level pressure
     is used, this criteria fails (0 pts).
  4. Scientific Accuracy & Unit Conversion (30 pts): AMBIENT_PRESSURE_HPA
     is numerically parsed and falls within the valid physiological range of
     500 to 700. (Fails if ~1000 [used SLP] or ~60000 [forgot to convert Pa to hPa]).

Pass Threshold: 80 points with both the Variable Selection (30) and
Scientific Accuracy (30) criteria met.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tibetan_plateau_hypoxia_physiology(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/tibetan_plateau_hypoxia_physiology_result.json', tmp.name)
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
    # Criterion 1: Asian sector pressure map exported (20 pts)
    # ----------------------------------------------------------------
    plot_exists = result.get('map_plot_exists', False)
    plot_mtime = int(result.get('map_plot_mtime', 0))
    plot_size = int(result.get('map_plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 15000:
        score += 20
        feedback.append(f"Pressure map exported successfully ({plot_size} bytes).")
    elif plot_exists and plot_mtime >= task_start and plot_size >= 5000:
        score += 10
        feedback.append(f"Pressure map exported but file size is small ({plot_size} bytes, expected >=15KB).")
    else:
        feedback.append(f"Pressure map missing or not created during task "
                        f"(exists={plot_exists}, size={plot_size}, mtime={plot_mtime} vs start={task_start}).")

    # ----------------------------------------------------------------
    # Criterion 2: Report Formatting (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    target_region = result.get('target_region', '').strip()
    dataset_var = result.get('dataset_variable_used', '').strip()
    ambient_pres = result.get('ambient_pressure_hpa', '').strip()
    phys_factor = result.get('physiological_factor', '').strip()

    has_all_keys = bool(target_region and dataset_var and ambient_pres and phys_factor)

    if report_exists and report_mtime >= task_start and has_all_keys:
        score += 20
        feedback.append(f"Report correctly formatted with all required fields.")
    elif report_exists and report_mtime >= task_start:
        score += 10
        missing = [k for k, v in [
            ('TARGET_REGION', target_region),
            ('DATASET_VARIABLE_USED', dataset_var),
            ('AMBIENT_PRESSURE_HPA', ambient_pres),
            ('PHYSIOLOGICAL_FACTOR', phys_factor)
        ] if not v]
        feedback.append(f"Report is partial; missing or empty fields: {missing}.")
    else:
        feedback.append(f"Report missing or not created during task (exists={report_exists}).")

    # ----------------------------------------------------------------
    # Criterion 3: Variable Selection Accuracy (30 pts)
    # ----------------------------------------------------------------
    var_lower = dataset_var.lower()
    var_score = 0
    
    # Must explicitly show they picked surface pressure over SLP
    if 'pres' in var_lower and 'slp' not in var_lower:
        var_score = 30
        feedback.append(f"Correct variable selected: '{dataset_var}' (Surface Pressure).")
    elif 'surface pressure' in var_lower and 'sea level' not in var_lower:
        var_score = 30
        feedback.append(f"Correct variable selected: '{dataset_var}' (Surface Pressure).")
    elif 'slp' in var_lower or 'sea level' in var_lower:
        var_score = 0
        feedback.append(f"FAILED variable selection: Used Sea Level Pressure ('{dataset_var}'). SLP is artificially corrected and useless for hypoxia studies.")
    elif var_lower:
        # Some ambiguous answer
        var_score = 0
        feedback.append(f"Unclear or incorrect variable selected: '{dataset_var}'. Expected 'pres'.")
    else:
        var_score = 0
        feedback.append("Variable selection not reported.")
    
    score += var_score

    # ----------------------------------------------------------------
    # Criterion 4: Scientific Accuracy & Unit Conversion (30 pts)
    # ----------------------------------------------------------------
    acc_score = 0
    
    if ambient_pres:
        # Extract the first valid floating point or integer number from the string
        match = re.search(r'[-+]?\d*\.\d+|\d+', ambient_pres)
        if match:
            try:
                pres_val = float(match.group())
                
                # The Tibetan Plateau at surface averages ~500 to ~650 hPa in July depending on exact grid cell
                if 500 <= pres_val <= 700:
                    acc_score = 30
                    feedback.append(f"Scientific accuracy passed: AMBIENT_PRESSURE_HPA ({pres_val} hPa) is physically accurate and units were converted correctly.")
                elif 50000 <= pres_val <= 70000:
                    acc_score = 0
                    feedback.append(f"Scientific accuracy failed: AMBIENT_PRESSURE_HPA ({pres_val}) is in Pascals, not hPa. You forgot to convert units.")
                elif 950 <= pres_val <= 1050:
                    acc_score = 0
                    feedback.append(f"Scientific accuracy failed: AMBIENT_PRESSURE_HPA ({pres_val} hPa) indicates you measured Sea Level Pressure, which incorrectly assumes 0m elevation.")
                else:
                    acc_score = 0
                    feedback.append(f"Scientific accuracy failed: AMBIENT_PRESSURE_HPA ({pres_val} hPa) is outside the expected Tibetan Plateau surface range (500-700 hPa).")
            except ValueError:
                acc_score = 0
                feedback.append(f"Scientific accuracy failed: Could not parse numerical value from '{ambient_pres}'.")
        else:
            acc_score = 0
            feedback.append(f"Scientific accuracy failed: Could not extract number from AMBIENT_PRESSURE_HPA ('{ambient_pres}').")
    else:
        acc_score = 0
        feedback.append("Scientific accuracy failed: AMBIENT_PRESSURE_HPA not reported.")

    score += acc_score

    # Determine pass/fail
    # Must get 80+ points AND specifically pass the two scientific domain knowledge criteria
    key_criteria_met = (var_score == 30) and (acc_score == 30)
    passed = (score >= 80) and key_criteria_met

    if not key_criteria_met:
        feedback.append("FATAL: Failed to meet core scientific criteria (variable selection and accurate unit conversion).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "plot_score": score,
            "variable_chosen": dataset_var,
            "pressure_reported": ambient_pres
        }
    }