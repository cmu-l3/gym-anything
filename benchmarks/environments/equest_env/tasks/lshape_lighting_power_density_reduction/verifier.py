#!/usr/bin/env python3
"""
Verifier for lshape_lighting_power_density_reduction task.

The agent (LEED consultant) must:
  - Reduce LIGHTING-W/AREA from 1.3 to 1.05 for ALL spaces currently at 1.3
  - Reduce EQUIPMENT-W/AREA from 1.5 to 1.2 for ALL spaces currently at 1.5
  - Run the full annual simulation
  - Save the project

Scoring (100 points total):
  - sim_file_is_new: 15 pts
  - All LPD spaces corrected (lpd13_remaining == 0): 15 pts bonus
  - Lighting corrected proportionally: up to 40 pts
      = 40 × (baseline_lpd13 - lpd13_remaining) / baseline_lpd13
  - All equipment spaces corrected (equip15_remaining == 0): 10 pts bonus
  - Equipment corrected proportionally: up to 20 pts
      = 20 × (baseline_equip15 - equip15_remaining) / baseline_equip15
      (baseline_equip15 assumed equal to baseline_lpd13 — same office spaces)

Pass threshold: >= 60 points AND sim_file_is_new AND lpd105_count > 0.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\lshape_lighting_power_density_reduction_result.json"


def verify_lshape_lighting_power_density_reduction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {result}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file (export may have failed or task not completed): {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []

    # Criterion 1: Simulation ran during this session (15 pts)
    sim_is_new = result.get('sim_file_is_new', False)
    if sim_is_new:
        score += 15
        feedback_parts.append("Simulation ran successfully during this session (+15).")
    elif result.get('sim_file_exists', False):
        feedback_parts.append("Simulation output found but predates task start.")
    else:
        feedback_parts.append("MISSING: No simulation output (.SIM) file — simulation not run.")

    # Baseline and current counts
    baseline = result.get('baseline_lpd13_count', 0)
    try:
        baseline = int(baseline)
    except (ValueError, TypeError):
        baseline = 0

    lpd13_remaining = result.get('lpd13_remaining_count', 0)
    try:
        lpd13_remaining = int(lpd13_remaining)
    except (ValueError, TypeError):
        lpd13_remaining = baseline  # assume nothing changed if parse fails

    lpd105_count = result.get('lpd105_count', 0)
    try:
        lpd105_count = int(lpd105_count)
    except (ValueError, TypeError):
        lpd105_count = 0

    equip15_remaining = result.get('equip15_remaining_count', 0)
    try:
        equip15_remaining = int(equip15_remaining)
    except (ValueError, TypeError):
        equip15_remaining = baseline  # assume nothing changed

    equip12_count = result.get('equip12_count', 0)
    try:
        equip12_count = int(equip12_count)
    except (ValueError, TypeError):
        equip12_count = 0

    # Criterion 2: All LPD spaces corrected — none remaining at 1.3 (15 pts bonus)
    if baseline > 0 and lpd13_remaining == 0:
        score += 15
        feedback_parts.append(f"All {baseline} LIGHTING-W/AREA=1.3 spaces corrected — none remaining (+15).")
    elif lpd13_remaining > 0:
        feedback_parts.append(f"{lpd13_remaining}/{baseline} spaces still have LIGHTING-W/AREA=1.3 (not fully corrected).")

    # Criterion 3: Lighting corrected proportionally (up to 40 pts)
    if baseline > 0:
        corrected = baseline - lpd13_remaining
        lpd_score = int(40 * corrected / baseline)
        score += lpd_score
        feedback_parts.append(
            f"LPD: {corrected}/{baseline} spaces changed to 1.05 W/ft² (+{lpd_score}). "
            f"New count at 1.05: {lpd105_count}."
        )
    else:
        feedback_parts.append("Baseline LPD count not recorded (setup may have failed).")

    # Criterion 4: All equipment spaces corrected (10 pts bonus)
    baseline_equip = baseline  # same private-office spaces
    if baseline_equip > 0 and equip15_remaining == 0:
        score += 10
        feedback_parts.append(f"All EQUIPMENT-W/AREA=1.5 spaces corrected to 1.2 (+10).")
    elif equip15_remaining > 0:
        feedback_parts.append(f"{equip15_remaining} spaces still have EQUIPMENT-W/AREA=1.5.")

    # Criterion 5: Equipment corrected proportionally (up to 20 pts)
    if baseline_equip > 0:
        equip_corrected = baseline_equip - equip15_remaining
        equip_score = int(20 * equip_corrected / baseline_equip)
        score += equip_score
        feedback_parts.append(
            f"Equipment: {equip_corrected}/{baseline_equip} spaces changed to 1.2 W/ft² (+{equip_score}). "
            f"New count at 1.2: {equip12_count}."
        )

    score = min(score, 100)
    passed = score >= 60 and sim_is_new and lpd105_count > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
