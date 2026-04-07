#!/usr/bin/env python3
"""
Verifier for eclipse_power_analysis@1

Scoring (total 100 pts, pass >= 60):
  - script_created (8): Script created during task window
  - sma_in_script (7): SMA value 6878.14 (±5) km present in script
  - inc_in_script (7): INC value 97.42 (±0.5) deg present in script
  - raan_in_script (5): RAAN value 195.0 (±2) deg present in script
  - eclipse_locator (10): Script contains EclipseLocator logic
  - propagation_30day (8): Propagation duration ~30 days
  - eclipse_data (5): Eclipse data file generated
  - report_written (5): Analysis report exists
  - num_eclipses (10): Total number of eclipses in [400, 520]
  - max_eclipse (12): Max eclipse duration in [30.0, 42.0] minutes
  - avg_eclipse (5): Average eclipse duration in [28.0, 40.0] minutes
  - eclipse_fraction (8): Eclipse fraction in [0.30, 0.44]
  - battery_conclusion (10): battery_adequate field is "YES" based on margin calc

Pass condition: score >= 60 AND max_eclipse_valid AND battery_conclusion_correct
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_eclipse_power_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_sma = metadata.get('expected_sma', 6878.14)
    expected_inc = metadata.get('expected_inc', 97.42)
    expected_raan = metadata.get('expected_raan', 195.0)
    num_eclipses_min = metadata.get('num_eclipses_min', 400)
    num_eclipses_max = metadata.get('num_eclipses_max', 520)
    max_ecl_min = metadata.get('max_eclipse_min_val', 30.0)
    max_ecl_max = metadata.get('max_eclipse_max_val', 42.0)
    avg_ecl_min = metadata.get('avg_eclipse_min_val', 28.0)
    avg_ecl_max = metadata.get('avg_eclipse_max_val', 40.0)
    frac_min = metadata.get('eclipse_fraction_min', 0.30)
    frac_max = metadata.get('eclipse_fraction_max', 0.44)

    scores = {
        "script_created": 8,
        "sma_in_script": 7,
        "inc_in_script": 7,
        "raan_in_script": 5,
        "eclipse_locator": 10,
        "propagation_30day": 8,
        "eclipse_data": 5,
        "report_written": 5,
        "num_eclipses": 10,
        "max_eclipse": 12,
        "avg_eclipse": 5,
        "eclipse_fraction": 8,
        "battery_conclusion": 10
    }

    total_score = 0
    feedback = []
    max_eclipse_ok = False
    battery_conclusion_ok = False

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Orbital params in script
    try:
        sma_val = float(task_result.get('script_sma', 0))
    except ValueError:
        sma_val = 0.0
    if abs(sma_val - expected_sma) <= 5.0:
        total_score += scores["sma_in_script"]
        feedback.append(f"SMA value correct in script ({sma_val}).")
    else:
        feedback.append(f"SMA incorrect or missing (found {sma_val}).")

    try:
        inc_val = float(task_result.get('script_inc', 0))
    except ValueError:
        inc_val = 0.0
    if abs(inc_val - expected_inc) <= 0.5:
        total_score += scores["inc_in_script"]
        feedback.append(f"INC value correct in script ({inc_val}).")
    else:
        feedback.append(f"INC incorrect or missing (found {inc_val}).")

    try:
        raan_val = float(task_result.get('script_raan', 0))
    except ValueError:
        raan_val = 0.0
    if abs(raan_val - expected_raan) <= 2.0:
        total_score += scores["raan_in_script"]
        feedback.append(f"RAAN value correct in script ({raan_val}).")
    else:
        feedback.append(f"RAAN incorrect or missing (found {raan_val}).")

    # 3. Eclipse locator logic
    if task_result.get('eclipse_locator', False):
        total_score += scores["eclipse_locator"]
        feedback.append("EclipseLocator configured.")
    else:
        feedback.append("EclipseLocator not explicitly found in script.")

    # 4. Propagation duration
    if task_result.get('propagation_30days', False):
        total_score += scores["propagation_30day"]
        feedback.append("Propagation duration configured for ~30 days.")
    else:
        feedback.append("Propagation duration does not match 30 days.")

    # 5. Eclipse data and report
    if task_result.get('eclipse_data_exists', False):
        total_score += scores["eclipse_data"]
        feedback.append("Eclipse event data file generated.")
    else:
        feedback.append("Eclipse event data file not found.")

    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_written"]
        feedback.append("Analysis report generated.")
    else:
        feedback.append("Analysis report not generated.")

    # 6. Check report values
    try:
        num_eclipses = float(task_result.get('num_eclipses', 0))
    except ValueError:
        num_eclipses = 0.0
    if num_eclipses_min <= num_eclipses <= num_eclipses_max:
        total_score += scores["num_eclipses"]
        feedback.append("Reported num eclipses in valid range.")
    else:
        feedback.append(f"Reported num eclipses invalid: {num_eclipses}")

    try:
        max_ecl = float(task_result.get('max_eclipse_min', 0))
    except ValueError:
        max_ecl = 0.0
    if max_ecl_min <= max_ecl <= max_ecl_max:
        total_score += scores["max_eclipse"]
        max_eclipse_ok = True
        feedback.append("Reported max eclipse duration in valid range.")
    else:
        feedback.append(f"Reported max eclipse duration invalid: {max_ecl}")

    try:
        avg_ecl = float(task_result.get('avg_eclipse_min', 0))
    except ValueError:
        avg_ecl = 0.0
    if avg_ecl_min <= avg_ecl <= avg_ecl_max:
        total_score += scores["avg_eclipse"]
        feedback.append("Reported avg eclipse duration in valid range.")
    else:
        feedback.append(f"Reported avg eclipse duration invalid: {avg_ecl}")

    try:
        frac = float(task_result.get('eclipse_fraction', 0))
    except ValueError:
        frac = 0.0
    if frac_min <= frac <= frac_max:
        total_score += scores["eclipse_fraction"]
        feedback.append("Reported eclipse fraction in valid range.")
    else:
        feedback.append(f"Reported eclipse fraction invalid: {frac}")

    # 7. Battery conclusion
    battery = task_result.get('battery_adequate', "UNKNOWN")
    if battery == "YES":
        total_score += scores["battery_conclusion"]
        battery_conclusion_ok = True
        feedback.append("Battery conclusion correct (YES).")
    else:
        feedback.append(f"Battery conclusion incorrect (found {battery}, expected YES).")

    passed = (total_score >= 60) and max_eclipse_ok and battery_conclusion_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }