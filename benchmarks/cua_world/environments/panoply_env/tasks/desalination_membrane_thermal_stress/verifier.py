#!/usr/bin/env python3
"""
Verifier for desalination_membrane_thermal_stress task.

Occupation: Civil/Chemical Engineer
Industry: Water Infrastructure / Desalination
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. February map exported (20 pts): egypt_coasts_feb.png exists,
     was created after task start, and has size >= 15KB.
  2. August map exported (20 pts): egypt_coasts_aug.png exists,
     was created after task start, and has size >= 15KB.
  3. Report structure (20 pts): thermal_envelope_report.txt exists,
     was created after task start, and contains all 5 required fields.
  4. Thermal accuracy (30 pts): The four numeric SST values fall within the
     correct NOAA climatological ranges:
       - Med Feb: 14.0 - 19.0 (7.5 pts)
       - Med Aug: 25.0 - 29.5 (7.5 pts)
       - Red Sea Feb: 21.0 - 26.5 (7.5 pts)
       - Red Sea Aug: 28.5 - 34.0 (7.5 pts)
  5. Peak stress ID (10 pts): HIGHEST_PEAK_STRESS correctly identified as "Red Sea".
"""

import json
import os
import re
import tempfile


def extract_number(s):
    """Extract first floating point or integer from string."""
    match = re.search(r'-?\d+\.?\d*', str(s))
    if match:
        return float(match.group())
    return None


def verify_desalination_membrane_thermal_stress(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/desalination_membrane_thermal_stress_result.json', tmp.name)
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
    # Criterion 1: February map exported (20 pts)
    # ----------------------------------------------------------------
    feb_exists = result.get('feb_plot_exists', False)
    feb_mtime = int(result.get('feb_plot_mtime', 0))
    feb_size = int(result.get('feb_plot_size', 0))

    if feb_exists and feb_mtime >= task_start and feb_size >= 15000:
        score += 20
        feedback.append(f"Feb map exported ({feb_size} bytes)")
    elif feb_exists and feb_mtime >= task_start and feb_size > 0:
        score += 10
        feedback.append(f"Feb map exported but small ({feb_size} bytes)")
    else:
        feedback.append(f"Feb map missing or invalid (exists={feb_exists}, size={feb_size}, mtime={feb_mtime})")

    # ----------------------------------------------------------------
    # Criterion 2: August map exported (20 pts)
    # ----------------------------------------------------------------
    aug_exists = result.get('aug_plot_exists', False)
    aug_mtime = int(result.get('aug_plot_mtime', 0))
    aug_size = int(result.get('aug_plot_size', 0))

    if aug_exists and aug_mtime >= task_start and aug_size >= 15000:
        score += 20
        feedback.append(f"Aug map exported ({aug_size} bytes)")
    elif aug_exists and aug_mtime >= task_start and aug_size > 0:
        score += 10
        feedback.append(f"Aug map exported but small ({aug_size} bytes)")
    else:
        feedback.append(f"Aug map missing or invalid (exists={aug_exists}, size={aug_size}, mtime={aug_mtime})")

    # ----------------------------------------------------------------
    # Criterion 3: Report structure (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    med_feb_raw = result.get('med_feb', '').strip()
    med_aug_raw = result.get('med_aug', '').strip()
    red_sea_feb_raw = result.get('red_sea_feb', '').strip()
    red_sea_aug_raw = result.get('red_sea_aug', '').strip()
    peak_stress_raw = result.get('peak_stress', '').strip()

    all_keys_present = bool(med_feb_raw and med_aug_raw and red_sea_feb_raw and red_sea_aug_raw and peak_stress_raw)

    if report_exists and report_mtime >= task_start and all_keys_present:
        score += 20
        feedback.append("Report structurally complete")
    elif report_exists and report_mtime >= task_start:
        score += 10
        missing = []
        if not med_feb_raw: missing.append('MED_FEB_SST')
        if not med_aug_raw: missing.append('MED_AUG_SST')
        if not red_sea_feb_raw: missing.append('RED_SEA_FEB_SST')
        if not red_sea_aug_raw: missing.append('RED_SEA_AUG_SST')
        if not peak_stress_raw: missing.append('HIGHEST_PEAK_STRESS')
        feedback.append(f"Report partial - missing: {missing}")
    else:
        feedback.append(f"Report missing or not created during task (exists={report_exists})")

    # ----------------------------------------------------------------
    # Criterion 4: Thermal accuracy (30 pts - 7.5 per correct range)
    # ----------------------------------------------------------------
    med_feb_val = extract_number(med_feb_raw)
    med_aug_val = extract_number(med_aug_raw)
    red_sea_feb_val = extract_number(red_sea_feb_raw)
    red_sea_aug_val = extract_number(red_sea_aug_raw)

    numeric_points = 0
    if med_feb_val is not None:
        if 14.0 <= med_feb_val <= 19.0:
            numeric_points += 7.5
            feedback.append(f"MED_FEB_SST={med_feb_val} within valid range")
        else:
            feedback.append(f"MED_FEB_SST={med_feb_val} OUTSIDE valid range [14.0-19.0]")
    
    if med_aug_val is not None:
        if 25.0 <= med_aug_val <= 29.5:
            numeric_points += 7.5
            feedback.append(f"MED_AUG_SST={med_aug_val} within valid range")
        else:
            feedback.append(f"MED_AUG_SST={med_aug_val} OUTSIDE valid range [25.0-29.5]")
            
    if red_sea_feb_val is not None:
        if 21.0 <= red_sea_feb_val <= 26.5:
            numeric_points += 7.5
            feedback.append(f"RED_SEA_FEB_SST={red_sea_feb_val} within valid range")
        else:
            feedback.append(f"RED_SEA_FEB_SST={red_sea_feb_val} OUTSIDE valid range [21.0-26.5]")
            
    if red_sea_aug_val is not None:
        if 28.5 <= red_sea_aug_val <= 34.0:
            numeric_points += 7.5
            feedback.append(f"RED_SEA_AUG_SST={red_sea_aug_val} within valid range")
        else:
            feedback.append(f"RED_SEA_AUG_SST={red_sea_aug_val} OUTSIDE valid range [28.5-34.0]")

    score += numeric_points

    # ----------------------------------------------------------------
    # Criterion 5: Peak stress ID (10 pts)
    # ----------------------------------------------------------------
    if peak_stress_raw.lower() in ["red sea", "red_sea", "red sea ", "the red sea"]:
        score += 10
        feedback.append("HIGHEST_PEAK_STRESS correctly identified as Red Sea")
    elif peak_stress_raw:
        feedback.append(f"HIGHEST_PEAK_STRESS incorrectly identified as '{peak_stress_raw}'")

    # Evaluate final
    score = min(100, int(score))
    # Key criteria: Both maps exported, report created, and at least 2 temperatures correct
    key_criteria_met = feb_exists and aug_exists and report_exists and numeric_points >= 15.0
    passed = (score >= 80) and key_criteria_met

    if passed:
        feedback.insert(0, f"SUCCESS (Score {score}/100)")
    else:
        feedback.insert(0, f"FAILED (Score {score}/100, pass threshold 80 with key criteria)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "feb_plot_size": feb_size,
            "aug_plot_size": aug_size,
            "med_feb_val": med_feb_val,
            "med_aug_val": med_aug_val,
            "red_sea_feb_val": red_sea_feb_val,
            "red_sea_aug_val": red_sea_aug_val,
            "peak_stress_val": peak_stress_raw
        }
    }