#!/usr/bin/env python3
"""
Verifier for middle_floor_comfort_roof_upgrade task.

The agent (energy auditor) must implement two ECMs:
  ECM 1 — Thermostat reset for all 5 Middle Floor (M.*) conditioned zones:
    - DESIGN-COOL-T: 75 → 76°F
    - DESIGN-HEAT-T: 72 → 71°F
  ECM 2 — High-reflectance cool roof:
    - Roof Construction ABSORPTANCE: 0.6 → 0.35
  Then run the full annual simulation and save the project.

Scoring (100 points total):
  - sim_file_is_new: 10 pts
  - Roof ABSORPTANCE corrected to 0.35 (±0.005): 25 pts
  - DESIGN-COOL-T corrected per M.* zone (≈76 ±0.5): 7 pts × 5 = 35 pts
  - DESIGN-HEAT-T corrected per M.* zone (≈71 ±0.5): 6 pts × 5 = 30 pts

Pass threshold: >= 60 points AND sim_file_is_new.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\middle_floor_comfort_roof_upgrade_result.json"


def verify_middle_floor_comfort_roof_upgrade(traj, env_info, task_info):
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

    # Criterion 1: Simulation ran during this session (10 pts)
    sim_is_new = result.get('sim_file_is_new', False)
    if sim_is_new:
        score += 10
        feedback_parts.append("Simulation ran successfully during this session (+10).")
    elif result.get('sim_file_exists', False):
        feedback_parts.append("Simulation output found but predates task start.")
    else:
        feedback_parts.append("MISSING: No simulation output (.SIM) file — simulation not run.")

    # Criterion 2: Roof ABSORPTANCE corrected to 0.35 (25 pts)
    roof_abs = result.get('roof_absorptance', -1)
    try:
        roof_abs = float(roof_abs)
    except (ValueError, TypeError):
        roof_abs = -1.0
    if roof_abs >= 0 and abs(roof_abs - 0.35) <= 0.005:
        score += 25
        feedback_parts.append(f"Roof ABSORPTANCE correctly set to {roof_abs:.4f} (target 0.35) (+25).")
    elif roof_abs >= 0:
        feedback_parts.append(f"Roof ABSORPTANCE = {roof_abs:.4f} (expected 0.35 for cool roof).")
    else:
        feedback_parts.append("Roof ABSORPTANCE not found in saved project.")

    # Criterion 3: DESIGN-COOL-T corrected to 76 (7 pts per zone, max 35)
    cool_count = result.get('cool_t_corrected_count', 0)
    try:
        cool_count = int(cool_count)
    except (ValueError, TypeError):
        cool_count = 0
    cool_score = cool_count * 7
    score += cool_score
    if cool_count == 5:
        feedback_parts.append(f"All 5 Middle Floor zones DESIGN-COOL-T correctly raised to 76°F (+{cool_score}).")
    elif cool_count > 0:
        feedback_parts.append(f"{cool_count}/5 Middle Floor zones DESIGN-COOL-T corrected to 76°F (+{cool_score}).")
    else:
        feedback_parts.append("No Middle Floor zones have DESIGN-COOL-T=76 (target: all M.* zones).")

    # Criterion 4: DESIGN-HEAT-T corrected to 71 (6 pts per zone, max 30)
    heat_count = result.get('heat_t_corrected_count', 0)
    try:
        heat_count = int(heat_count)
    except (ValueError, TypeError):
        heat_count = 0
    heat_score = heat_count * 6
    score += heat_score
    if heat_count == 5:
        feedback_parts.append(f"All 5 Middle Floor zones DESIGN-HEAT-T correctly lowered to 71°F (+{heat_score}).")
    elif heat_count > 0:
        feedback_parts.append(f"{heat_count}/5 Middle Floor zones DESIGN-HEAT-T corrected to 71°F (+{heat_score}).")
    else:
        feedback_parts.append("No Middle Floor zones have DESIGN-HEAT-T=71 (target: all M.* zones).")

    score = min(score, 100)
    passed = score >= 60 and sim_is_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
