#!/usr/bin/env python3
"""
Verifier for naval_asw_sonar_thermal_amplitude task.

Occupation: ASW Oceanographer
Industry: Defense / Naval Oceanography
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Plot exported (20 pts): sst_amplitude_aug_feb.png exists,
     was created after task start, and size >= 20KB.
  2. Report structure complete (20 pts): thermal_amplitude_report.txt exists
     and has all 6 required fields filled.
  3. Months correctly indicated (20 pts): August and February must be stated.
  4. Correct amplitude value (20 pts): MAX_AMPLITUDE_C between 16.0 and 24.0.
  5. Correct Region Identified (20 pts): Mentions Yellow Sea, Sea of Japan, 
     NW Atlantic, etc.
"""

import json
import os
import tempfile
import re

def verify_naval_asw_sonar_thermal_amplitude(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/naval_asw_sonar_thermal_amplitude_result.json', tmp.name)
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
    # Criterion 1: Plot exported (20 pts)
    # ----------------------------------------------------------------
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 20000:
        score += 20
        feedback.append(f"Difference plot exported ({plot_size} bytes)")
    elif plot_exists and plot_mtime >= task_start and plot_size >= 5000:
        score += 10
        feedback.append(f"Difference plot present but small ({plot_size} bytes, expected >=20KB)")
    else:
        feedback.append(f"Difference plot missing or not created during task (exists={plot_exists})")

    # ----------------------------------------------------------------
    # Evaluate Report Fields
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    if not (report_exists and report_mtime >= task_start):
        feedback.append("Report missing or not created during task")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    assessment_type = result.get('assessment_type', '').strip()
    month_1 = result.get('month_1', '').strip()
    month_2 = result.get('month_2', '').strip()
    max_amp_raw = result.get('max_amplitude', '').strip()
    peak_region = result.get('peak_region', '').strip()
    tact_impact = result.get('tactical_impact', '').strip()

    has_all_fields = bool(assessment_type and month_1 and month_2 and max_amp_raw and peak_region and tact_impact)

    # ----------------------------------------------------------------
    # Criterion 2: Report structure complete (20 pts)
    # ----------------------------------------------------------------
    if has_all_fields:
        score += 20
        feedback.append("Report structure is complete")
    else:
        missing = [f for f, v in [
            ('ASSESSMENT_TYPE', assessment_type),
            ('MONTH_1', month_1),
            ('MONTH_2', month_2),
            ('MAX_AMPLITUDE_C', max_amp_raw),
            ('PEAK_REGION', peak_region),
            ('TACTICAL_IMPACT', tact_impact)
        ] if not v]
        feedback.append(f"Report missing required fields: {missing}")

    # ----------------------------------------------------------------
    # Criterion 3: Months correctly indicated (20 pts)
    # ----------------------------------------------------------------
    month_1_ok = 'aug' in month_1.lower()
    month_2_ok = 'feb' in month_2.lower()
    if month_1_ok and month_2_ok:
        score += 20
        feedback.append("Months correctly identified (August and February)")
    elif month_1_ok or month_2_ok:
        score += 10
        feedback.append(f"Only one month correctly identified (M1: '{month_1}', M2: '{month_2}')")
    else:
        feedback.append(f"Months incorrectly identified (M1: '{month_1}', M2: '{month_2}')")

    # ----------------------------------------------------------------
    # Criterion 4: Correct amplitude value (20 pts)
    # ----------------------------------------------------------------
    amp_ok = False
    try:
        amp_val_str = re.sub(r'[^\d\.\-]', '', max_amp_raw)
        if amp_val_str:
            amp_val = float(amp_val_str)
            amp_val = abs(amp_val) # Support absolute difference if agent subtracted in reverse
            if 16.0 <= amp_val <= 24.0:
                score += 20
                amp_ok = True
                feedback.append(f"MAX_AMPLITUDE_C={amp_val:.1f} is within valid delta range (16.0-24.0)")
            else:
                feedback.append(f"MAX_AMPLITUDE_C={amp_val:.1f} is outside the valid difference range (16.0-24.0)")
        else:
            feedback.append("MAX_AMPLITUDE_C contains no valid number")
    except ValueError:
        feedback.append("Could not parse MAX_AMPLITUDE_C as a number")

    # ----------------------------------------------------------------
    # Criterion 5: Correct Region Identified (20 pts)
    # ----------------------------------------------------------------
    valid_keywords = ['yellow', 'japan', 'kuroshio', 'atlantic', 'new england', 'canad', 'maritime', 'gulf stream', 'china', 'korea']
    region_lower = peak_region.lower()
    region_found = any(k in region_lower for k in valid_keywords)
    if region_found:
        score += 20
        feedback.append(f"Valid peak region identified ('{peak_region}')")
    else:
        feedback.append(f"Peak region not recognized as a maximum amplitude zone ('{peak_region}')")

    # Must have correct amplitude value to pass (prevents random reporting of absolute temps)
    passed = (score >= 80) and amp_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }