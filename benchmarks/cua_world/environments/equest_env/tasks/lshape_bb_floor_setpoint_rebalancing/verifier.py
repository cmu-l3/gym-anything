#!/usr/bin/env python3
"""
Verifier for lshape_bb_floor_setpoint_rebalancing task.

The agent (building commissioning engineer) must update ALL BB.* zones and systems:
  - DESIGN-COOL-T: 75 → 77°F (all 5 BB conditioned zones)
  - DESIGN-HEAT-T: 72 → 70°F (all 5 BB conditioned zones)
  - SUPPLY-STATIC:  1.25 → 1.1 in. w.g. (all 5 BB PSZ systems)
Then run the full annual simulation and save the project.

Scoring (100 points total):
  - sim_file_is_new: 10 pts
  - DESIGN-COOL-T corrected per zone (≈77 ±0.5): 8 pts × 5 = 40 pts
  - DESIGN-HEAT-T corrected per zone (≈70 ±0.5): 8 pts × 5 = 40 pts
  - SUPPLY-STATIC corrected per system (≈1.1 ±0.02): 2 pts × 5 = 10 pts

Pass threshold: >= 60 points AND sim_file_is_new.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\lshape_bb_floor_setpoint_rebalancing_result.json"


def verify_lshape_bb_floor_setpoint_rebalancing(traj, env_info, task_info):
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

    # Criterion 2: DESIGN-COOL-T corrected to 77 (8 pts per zone, max 40)
    cool_count = result.get('cool_t_corrected_count', 0)
    try:
        cool_count = int(cool_count)
    except (ValueError, TypeError):
        cool_count = 0
    cool_score = cool_count * 8
    score += cool_score
    if cool_count == 5:
        feedback_parts.append(f"All 5 BB zones DESIGN-COOL-T correctly raised to 77°F (+{cool_score}).")
    elif cool_count > 0:
        feedback_parts.append(f"{cool_count}/5 BB zones DESIGN-COOL-T corrected to 77°F (+{cool_score}).")
    else:
        feedback_parts.append("No BB zones have DESIGN-COOL-T=77 (target: all BB conditioned zones).")

    # Criterion 3: DESIGN-HEAT-T corrected to 70 (8 pts per zone, max 40)
    heat_count = result.get('heat_t_corrected_count', 0)
    try:
        heat_count = int(heat_count)
    except (ValueError, TypeError):
        heat_count = 0
    heat_score = heat_count * 8
    score += heat_score
    if heat_count == 5:
        feedback_parts.append(f"All 5 BB zones DESIGN-HEAT-T correctly lowered to 70°F (+{heat_score}).")
    elif heat_count > 0:
        feedback_parts.append(f"{heat_count}/5 BB zones DESIGN-HEAT-T corrected to 70°F (+{heat_score}).")
    else:
        feedback_parts.append("No BB zones have DESIGN-HEAT-T=70 (target: all BB conditioned zones).")

    # Criterion 4: SUPPLY-STATIC corrected to 1.1 (2 pts per system, max 10)
    static_count = result.get('supply_static_corrected_count', 0)
    try:
        static_count = int(static_count)
    except (ValueError, TypeError):
        static_count = 0
    static_score = static_count * 2
    score += static_score
    if static_count == 5:
        feedback_parts.append(f"All 5 BB systems SUPPLY-STATIC correctly reduced to 1.1 in. w.g. (+{static_score}).")
    elif static_count > 0:
        feedback_parts.append(f"{static_count}/5 BB systems SUPPLY-STATIC corrected (+{static_score}).")
    else:
        feedback_parts.append("No BB systems have SUPPLY-STATIC=1.1 (target: all BB PSZ systems).")

    score = min(score, 100)
    passed = score >= 60 and sim_is_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
