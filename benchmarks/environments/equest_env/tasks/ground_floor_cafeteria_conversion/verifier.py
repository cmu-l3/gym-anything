#!/usr/bin/env python3
"""
Verifier for ground_floor_cafeteria_conversion task.

The agent must:
1. Update Space G.E02 loads (Lighting=1.5, Equip=8.0, Area/Person=15)
2. Update Zone G.E02 airflow (Exhaust Flow=2000)
3. Run simulation and save.

Scoring (100 pts total):
- Simulation run during session: 10 pts
- Lighting LPD Correct (1.5 ±0.1): 20 pts
- Equipment LPD Correct (8.0 ±0.2): 20 pts
- Occupancy Density Correct (15 ±1): 20 pts
- Exhaust Flow Correct (2000 ±50): 30 pts

Pass threshold: 70 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\task_result.json"

def verify_ground_floor_cafeteria_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load results
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Simulation Check (10 pts)
    if result.get('sim_file_is_new', False):
        score += 10
        feedback.append("Simulation run successfully (+10).")
    else:
        feedback.append("Simulation NOT run during session (0).")

    # 2. Lighting Load (20 pts)
    val = float(result.get('lighting_lpd', -1))
    if 1.4 <= val <= 1.6:
        score += 20
        feedback.append(f"Lighting LPD correct ({val}) (+20).")
    else:
        feedback.append(f"Lighting LPD incorrect (Found: {val}, Expected: 1.5).")

    # 3. Equipment Load (20 pts)
    val = float(result.get('equip_lpd', -1))
    if 7.8 <= val <= 8.2:
        score += 20
        feedback.append(f"Equipment LPD correct ({val}) (+20).")
    else:
        feedback.append(f"Equipment LPD incorrect (Found: {val}, Expected: 8.0).")

    # 4. Occupancy Density (20 pts)
    val = float(result.get('area_per_person', -1))
    if 14.0 <= val <= 16.0:
        score += 20
        feedback.append(f"Occupancy Density correct ({val}) (+20).")
    else:
        feedback.append(f"Occupancy Density incorrect (Found: {val}, Expected: 15).")

    # 5. Exhaust Flow (30 pts)
    val = float(result.get('exhaust_flow', -1))
    if 1950 <= val <= 2050:
        score += 30
        feedback.append(f"Exhaust Flow correct ({val}) (+30).")
    else:
        feedback.append(f"Exhaust Flow incorrect (Found: {val}, Expected: 2000).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }