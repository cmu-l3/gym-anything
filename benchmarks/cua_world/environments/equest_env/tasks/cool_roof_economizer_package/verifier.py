#!/usr/bin/env python3
"""
Verifier for cool_roof_economizer_package task.

The agent (sustainability specialist) must:
1. Reduce EWall Construction ABSORPTANCE from 0.6 to 0.45
2. Reduce Roof Construction ABSORPTANCE from 0.6 to 0.45
3. Lower DRYBULB-LIMIT on all 5 Ground Floor (G.*) PSZ systems from 70 to 65
4. Run the full annual simulation
5. Save the project

Scoring (100 points total):
  - sim_file_is_new: 15 pts  (simulation ran during this session)
  - ewall_absorptance == 0.45 (±0.005): 20 pts
  - roof_absorptance == 0.45 (±0.005):  20 pts
  - each G.* system DRYBULB-LIMIT corrected to 65: 9 pts × 5 = 45 pts

Pass threshold: >= 60 points AND sim_file_is_new.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\cool_roof_economizer_package_result.json"
G_SYSTEMS = ['G.S11', 'G.E12', 'G.N13', 'G.W14', 'G.C15']


def verify_cool_roof_economizer_package(traj, env_info, task_info):
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
        feedback_parts.append("Simulation output found but predates task start (not run during task).")
    else:
        feedback_parts.append("MISSING: No simulation output (.SIM) file found — simulation not run.")

    # Criterion 2: EWall Construction ABSORPTANCE corrected to 0.45 (20 pts)
    ewall_abs = result.get('ewall_absorptance', -1)
    try:
        ewall_abs = float(ewall_abs)
    except (ValueError, TypeError):
        ewall_abs = -1.0
    if ewall_abs >= 0 and abs(ewall_abs - 0.45) <= 0.005:
        score += 20
        feedback_parts.append(f"EWall ABSORPTANCE correctly set to {ewall_abs:.4f} (target 0.45) (+20).")
    elif ewall_abs >= 0:
        feedback_parts.append(f"EWall ABSORPTANCE = {ewall_abs:.4f} (expected 0.45).")
    else:
        feedback_parts.append("EWall ABSORPTANCE not found in saved project (project may not have been saved).")

    # Criterion 3: Roof Construction ABSORPTANCE corrected to 0.45 (20 pts)
    roof_abs = result.get('roof_absorptance', -1)
    try:
        roof_abs = float(roof_abs)
    except (ValueError, TypeError):
        roof_abs = -1.0
    if roof_abs >= 0 and abs(roof_abs - 0.45) <= 0.005:
        score += 20
        feedback_parts.append(f"Roof ABSORPTANCE correctly set to {roof_abs:.4f} (target 0.45) (+20).")
    elif roof_abs >= 0:
        feedback_parts.append(f"Roof ABSORPTANCE = {roof_abs:.4f} (expected 0.45).")
    else:
        feedback_parts.append("Roof ABSORPTANCE not found in saved project.")

    # Criterion 4: G.* systems DRYBULB-LIMIT corrected to 65 (9 pts per system, max 45)
    g_count = result.get('g_drybulb_corrected_count', 0)
    try:
        g_count = int(g_count)
    except (ValueError, TypeError):
        g_count = 0
    g_score = g_count * 9
    score += g_score
    if g_count == 5:
        feedback_parts.append(f"All 5 Ground Floor systems DRYBULB-LIMIT corrected to 65 (+{g_score}).")
    elif g_count > 0:
        feedback_parts.append(f"{g_count}/5 Ground Floor systems DRYBULB-LIMIT corrected to 65 (+{g_score}).")
    else:
        feedback_parts.append("No Ground Floor systems have DRYBULB-LIMIT=65 (target: all 5 G.* systems).")

    score = min(score, 100)
    passed = score >= 60 and sim_is_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
