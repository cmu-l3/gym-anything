#!/usr/bin/env python3
"""
Verifier for top_floor_rtu_efficiency_upgrade task.

The agent (mechanical engineer) must update ALL 5 Top Floor (T.*) PSZ systems:
  - COOLING-EIR: 0.34565 → 0.28571
  - FURNACE-HIR: 1.24069 → 1.11111
  - SUPPLY-EFF:  0.53    → 0.65
Then run the full annual simulation and save the project.

Scoring (100 points total):
  - sim_file_is_new: 10 pts
  - COOLING-EIR corrected per system (≈0.28571 ±0.005): 8 pts × 5 = 40 pts
  - FURNACE-HIR corrected per system (≈1.11111 ±0.005): 6 pts × 5 = 30 pts
  - SUPPLY-EFF corrected per system  (≈0.65 ±0.005):    4 pts × 5 = 20 pts

Pass threshold: >= 60 points AND sim_file_is_new AND cooling_eir_corrected >= 3.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\top_floor_rtu_efficiency_upgrade_result.json"


def verify_top_floor_rtu_efficiency_upgrade(traj, env_info, task_info):
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

    # Criterion 2: COOLING-EIR corrected (8 pts per system, max 40)
    eir_count = result.get('cooling_eir_corrected_count', 0)
    try:
        eir_count = int(eir_count)
    except (ValueError, TypeError):
        eir_count = 0
    eir_score = eir_count * 8
    score += eir_score
    if eir_count == 5:
        feedback_parts.append(f"All 5 T.* systems COOLING-EIR correctly set to 0.28571 (+{eir_score}).")
    elif eir_count > 0:
        feedback_parts.append(f"{eir_count}/5 T.* systems COOLING-EIR corrected (+{eir_score}).")
    else:
        feedback_parts.append("No T.* systems have corrected COOLING-EIR (target 0.28571).")

    # Criterion 3: FURNACE-HIR corrected (6 pts per system, max 30)
    hir_count = result.get('furnace_hir_corrected_count', 0)
    try:
        hir_count = int(hir_count)
    except (ValueError, TypeError):
        hir_count = 0
    hir_score = hir_count * 6
    score += hir_score
    if hir_count == 5:
        feedback_parts.append(f"All 5 T.* systems FURNACE-HIR correctly set to 1.11111 (+{hir_score}).")
    elif hir_count > 0:
        feedback_parts.append(f"{hir_count}/5 T.* systems FURNACE-HIR corrected (+{hir_score}).")
    else:
        feedback_parts.append("No T.* systems have corrected FURNACE-HIR (target 1.11111).")

    # Criterion 4: SUPPLY-EFF corrected (4 pts per system, max 20)
    eff_count = result.get('supply_eff_corrected_count', 0)
    try:
        eff_count = int(eff_count)
    except (ValueError, TypeError):
        eff_count = 0
    eff_score = eff_count * 4
    score += eff_score
    if eff_count == 5:
        feedback_parts.append(f"All 5 T.* systems SUPPLY-EFF correctly set to 0.65 (+{eff_score}).")
    elif eff_count > 0:
        feedback_parts.append(f"{eff_count}/5 T.* systems SUPPLY-EFF corrected (+{eff_score}).")
    else:
        feedback_parts.append("No T.* systems have corrected SUPPLY-EFF (target 0.65).")

    score = min(score, 100)
    passed = score >= 60 and sim_is_new and eir_count >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
