#!/usr/bin/env python3
"""
Verifier for sahel_drought_teleconnection_analysis task.

Occupation: Agricultural Climatologist / Food Security Analyst
Industry: USDA Economic Research Service / Global Food Security Assessment
Difficulty: very_hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Sahel precipitation plot exported (25 pts): sahel_precip_july.png exists,
     was created after task start, and has size >= 15KB.
  2. Pacific SST plot exported (25 pts): pacific_sst_july.png exists,
     was created after task start, and has size >= 15KB.
  3. Teleconnection report with required fields (25 pts): teleconnection_report.txt
     exists, was created after task start, and contains ANALYSIS_REGION_1,
     ANALYSIS_REGION_2, TARGET_SEASON, and ENSO_CONNECTION fields.
  4. Correct ENSO teleconnection sign (25 pts): ENSO_CONNECTION is NEGATIVE.
     The Sahel-ENSO teleconnection is well-documented in the climate literature:
     - El Niño (warm equatorial Pacific) → reduced Sahel rainfall / drought
     - La Niña (cool equatorial Pacific) → enhanced Sahel rainfall
     This is a NEGATIVE relationship (warm SST anomaly → negative precip anomaly).
     The mandate provides this scientific guidance explicitly; the agent must
     read it and apply domain knowledge to classify the relationship correctly.
"""

import json
import os
import tempfile


def verify_sahel_drought_teleconnection_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/sahel_drought_teleconnection_analysis_result.json', tmp.name)
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
    # Criterion 1: Sahel precipitation plot exported (25 pts)
    # ----------------------------------------------------------------
    precip_exists = result.get('precip_plot_exists', False)
    precip_mtime = int(result.get('precip_plot_mtime', 0))
    precip_size = int(result.get('precip_plot_size', 0))

    if precip_exists and precip_mtime >= task_start and precip_size >= 15000:
        score += 25
        feedback.append(f"Sahel precipitation plot exported ({precip_size} bytes)")
    elif precip_exists and precip_mtime >= task_start and precip_size >= 5000:
        score += 12
        feedback.append(f"Precipitation plot present but small ({precip_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Sahel precipitation plot missing or not created during task "
                        f"(exists={precip_exists}, size={precip_size}, mtime={precip_mtime} vs start={task_start})")

    # ----------------------------------------------------------------
    # Criterion 2: Pacific SST plot exported (25 pts)
    # ----------------------------------------------------------------
    sst_exists = result.get('sst_plot_exists', False)
    sst_mtime = int(result.get('sst_plot_mtime', 0))
    sst_size = int(result.get('sst_plot_size', 0))

    if sst_exists and sst_mtime >= task_start and sst_size >= 15000:
        score += 25
        feedback.append(f"Pacific SST plot exported ({sst_size} bytes)")
    elif sst_exists and sst_mtime >= task_start and sst_size >= 5000:
        score += 12
        feedback.append(f"SST plot present but small ({sst_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Pacific SST plot missing or not created during task "
                        f"(exists={sst_exists}, size={sst_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Teleconnection report with required fields (25 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    region1 = result.get('analysis_region1', '').strip()
    region2 = result.get('analysis_region2', '').strip()
    season = result.get('target_season', '').strip()
    enso_conn = result.get('enso_connection', '').strip()
    precip_pattern = result.get('sahel_precip_pattern', '').strip()

    has_regions = bool(region1) and bool(region2)
    has_season = bool(season)
    has_enso = bool(enso_conn)

    if report_exists and report_mtime >= task_start and has_regions and has_enso:
        score += 25
        feedback.append(f"Teleconnection report complete "
                        f"(region1='{region1}', region2='{region2}', "
                        f"season='{season}', ENSO='{enso_conn}')")
    elif report_exists and report_mtime >= task_start and (has_regions or has_enso):
        score += 12
        missing = []
        if not has_regions:
            missing.append('ANALYSIS_REGION_1/2')
        if not has_enso:
            missing.append('ENSO_CONNECTION')
        feedback.append(f"Report partial — missing fields: {missing}")
    else:
        feedback.append(f"Teleconnection report missing or not created during task "
                        f"(exists={report_exists})")

    # ----------------------------------------------------------------
    # Criterion 4: Correct ENSO teleconnection sign (25 pts)
    # The Sahel-ENSO relationship is NEGATIVE: warm Pacific (El Niño) → Sahel drought.
    # The mandate explicitly explains this relationship. An agent that reads the
    # mandate AND has domain knowledge will correctly classify this as NEGATIVE.
    # ----------------------------------------------------------------
    enso_upper = enso_conn.upper().strip()
    if enso_upper == 'NEGATIVE' or enso_upper.startswith('NEGATIVE'):
        score += 25
        feedback.append("Correct: Sahel-ENSO teleconnection classified as NEGATIVE "
                        "(El Niño → drought; La Niña → enhanced rainfall)")
    elif 'NEGATIVE' in enso_upper:
        score += 20
        feedback.append(f"ENSO_CONNECTION contains 'NEGATIVE' (got '{enso_conn}')")
    elif enso_upper == 'POSITIVE' or 'POSITIVE' in enso_upper:
        score += 0
        feedback.append(f"Incorrect: ENSO_CONNECTION classified as POSITIVE "
                        f"(the Sahel-ENSO teleconnection is NEGATIVE — "
                        f"El Niño causes Sahel drought, La Niña enhances rainfall)")
    elif enso_upper == 'NEUTRAL' or 'NEUTRAL' in enso_upper:
        score += 0
        feedback.append(f"ENSO_CONNECTION classified as NEUTRAL — incorrect; "
                        f"the well-documented Sahel-ENSO teleconnection is NEGATIVE")
    else:
        feedback.append(f"Could not evaluate ENSO_CONNECTION: '{enso_conn}'")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
