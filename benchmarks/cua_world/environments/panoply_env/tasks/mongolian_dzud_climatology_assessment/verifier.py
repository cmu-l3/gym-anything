#!/usr/bin/env python3
"""
Verifier for mongolian_dzud_climatology_assessment task.

Occupation: Anticipatory Action Climatologist
Industry: Humanitarian / IFRC
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80 AND quant_score = 20):
  1. Precipitation Line Plot Export (20 pts)
  2. Winter Temperature Map Export (20 pts)
  3. Report Formatting and Existence (20 pts)
  4. Accuracy: Peak Pasture Month is July (20 pts)
  5. Scientific Extraction Accuracy (20 pts):
       - Peak Precip matches [1e-5, 5e-5] kg/m^2/s
       - January Mean Temp at 47N, 105E matches [-35, -15] Celsius
"""

import json
import os
import tempfile
import re

def verify_mongolian_dzud_climatology_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Securely retrieve result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/mongolian_dzud_climatology_assessment_result.json', tmp.name)
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
    # Criterion 1: Precipitation Line Plot (20 pts)
    # ----------------------------------------------------------------
    precip_exists = result.get('precip_plot_exists', False)
    precip_mtime = int(result.get('precip_plot_mtime', 0))
    precip_size = int(result.get('precip_plot_size', 0))

    if precip_exists and precip_mtime >= task_start and precip_size >= 15000:
        score += 20
        feedback.append(f"Precipitation line plot exported ({precip_size} bytes)")
    elif precip_exists and precip_mtime >= task_start and precip_size >= 5000:
        score += 10
        feedback.append(f"Precipitation line plot exported but small ({precip_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Precipitation line plot missing or not created during task (exists={precip_exists})")

    # ----------------------------------------------------------------
    # Criterion 2: Winter Temperature Map (20 pts)
    # ----------------------------------------------------------------
    temp_exists = result.get('temp_plot_exists', False)
    temp_mtime = int(result.get('temp_plot_mtime', 0))
    temp_size = int(result.get('temp_plot_size', 0))

    if temp_exists and temp_mtime >= task_start and temp_size >= 15000:
        score += 20
        feedback.append(f"Winter temperature map exported ({temp_size} bytes)")
    elif temp_exists and temp_mtime >= task_start and temp_size >= 5000:
        score += 10
        feedback.append(f"Winter temperature map exported but small ({temp_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Winter temperature map missing or not created during task (exists={temp_exists})")

    # ----------------------------------------------------------------
    # Criterion 3: Report Formatting (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    analysis_region = result.get('analysis_region', '').strip()
    peak_month = result.get('peak_pasture_month', '').strip()
    peak_precip = result.get('peak_precip_rate', '').strip()
    winter_month = result.get('coldest_winter_month', '').strip()
    jan_temp = result.get('january_mean_temp_c', '').strip()

    has_required = bool(analysis_region) and bool(peak_month) and bool(peak_precip) and bool(winter_month) and bool(jan_temp)

    if report_exists and report_mtime >= task_start and has_required:
        score += 20
        feedback.append("Report contains all required fields")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("Report is partial or missing some fields")
    else:
        feedback.append("Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 4: Peak Pasture Month Qualitative Identifier (20 pts)
    # ----------------------------------------------------------------
    if peak_month.lower() == 'july':
        score += 20
        feedback.append("Peak pasture month correctly identified as July")
    elif peak_month:
        feedback.append(f"Peak pasture month incorrect: expected July, got '{peak_month}'")

    # ----------------------------------------------------------------
    # Criterion 5: Quantitative Data Extraction (20 pts)
    # ----------------------------------------------------------------
    quant_score = 0
    try:
        # Match standard or scientific notation for precipitation
        precip_match = re.search(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', peak_precip)
        if precip_match:
            p_val = float(precip_match.group(0))
            if 1e-5 <= p_val <= 5e-5:
                quant_score += 10
                feedback.append(f"Peak precip rate '{p_val}' is in physically plausible range [1e-5, 5e-5]")
            else:
                feedback.append(f"Peak precip rate '{p_val}' outside expected range [1e-5, 5e-5]")
        else:
            feedback.append("Could not parse peak precip rate")
    except Exception:
        feedback.append("Error parsing peak precip rate")

    try:
        # Match simple floats/ints for temperature
        temp_match = re.search(r'[-+]?\d*\.?\d+', jan_temp)
        if temp_match:
            t_val = float(temp_match.group(0))
            if -35 <= t_val <= -15:
                quant_score += 10
                feedback.append(f"January mean temp '{t_val}' is in physically plausible range [-35, -15]")
            else:
                feedback.append(f"January mean temp '{t_val}' outside expected range [-35, -15]")
        else:
            feedback.append("Could not parse January mean temp")
    except Exception:
        feedback.append("Error parsing January mean temp")
        
    score += quant_score

    # To fully pass, the agent must nail the scientific quantities extraction
    passed = (score >= 80) and (quant_score == 20)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }