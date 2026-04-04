#!/usr/bin/env python3
"""
Verifier for top_floor_evap_precooling_retrofit task.

The agent must:
1. Configure Direct Evap Precooling on 5 Top Floor systems (T.S31, T.E32, T.N33, T.W34, T.C35).
   - EVAP-PRECOOL-TYPE = DIRECT
   - EVAP-PRECOOL-EFF = 0.85
   - EVAP-PUMP-PWR = 0.06
2. Run Simulation (verified by .SIM file timestamp).
3. Save project.

Scoring (100 pts total):
- Simulation Executed: 10 pts
- Per System (5 systems * 18 pts each = 90 pts):
  - Type Correct: 6 pts
  - Eff Correct: 6 pts
  - Pump Correct: 6 pts

Pass Threshold: 64 pts (Sim + ~3 full systems)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\top_floor_evap_precooling_retrofit_result.json"
TARGET_SYSTEMS = ["T.S31", "T.E32", "T.N33", "T.W34", "T.C35"]

def verify_top_floor_evap_precooling_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from environment
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation Run (10 pts)
    sim_run = result.get("sim_run_during_task", False)
    if sim_run:
        score += 10
        feedback_parts.append("Simulation executed successfully (+10).")
    else:
        feedback_parts.append("Simulation NOT run during task (0/10).")

    # 2. Verify Systems (90 pts)
    systems_data = result.get("systems", {})
    
    for sys_name in TARGET_SYSTEMS:
        sys_score = 0
        sys_feedback = []
        
        data = systems_data.get(sys_name, {})
        
        # Check Type (6 pts)
        val_type = data.get("Type", "NONE")
        if val_type == "DIRECT":
            sys_score += 6
        else:
            sys_feedback.append(f"Type={val_type} (expected DIRECT)")
            
        # Check Efficiency (6 pts)
        val_eff = data.get("Eff", 0.0)
        if 0.84 <= val_eff <= 0.86: # Tolerance +/- 0.01
            sys_score += 6
        else:
            sys_feedback.append(f"Eff={val_eff} (expected 0.85)")
            
        # Check Pump Power (6 pts)
        val_pump = data.get("Pump", 0.0)
        if 0.055 <= val_pump <= 0.065: # Tolerance +/- 0.005
            sys_score += 6
        else:
            sys_feedback.append(f"Pump={val_pump} (expected 0.06)")
            
        score += sys_score
        if sys_score < 18:
            feedback_parts.append(f"System {sys_name}: {sys_score}/18 pts. Issues: {', '.join(sys_feedback)}")

    # Final Check
    passed = (score >= 64) and sim_run
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }