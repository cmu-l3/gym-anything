#!/usr/bin/env python3
"""
Verifier for heat_pump_conversion_middle_floor task.

The agent must convert 5 Middle Floor (M.*) HVAC systems from Furnace to Heat Pump.
Parameters to verify per system:
1. HEAT-SOURCE = HEAT-PUMP
2. HEATING-EIR = 0.30488 (±0.005)
3. MIN-HP-T = 17 (±1.0)
4. HP-SUPP-SOURCE = ELECTRIC

Additionally, a simulation run (.SIM file generation) is required for the changes to be meaningful.

Scoring Breakdown (100 pts):
- Simulation ran during session: 10 pts
- Per System (5 systems total):
  - HEAT-SOURCE Correct: 6 pts * 5 = 30 pts
  - HEATING-EIR Correct: 5 pts * 5 = 25 pts
  - MIN-HP-T Correct:    3 pts * 5 = 15 pts
  - HP-SUPP-SOURCE Correct: 4 pts * 5 = 20 pts

Pass Threshold: 60 pts AND Simulation Ran AND at least 3 systems converted to Heat Pump.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\heat_pump_conversion_result.json"
TARGET_SYSTEMS = ["M.S21", "M.E22", "M.N23", "M.W24", "M.C25"]

def verify_heat_pump_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Load Result JSON from Container
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not read result file (task likely not attempted or export failed): {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Simulation Run (10 pts)
    sim_ran = result.get('sim_file_is_new', False)
    if sim_ran:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10).")
    elif result.get('sim_file_exists', False):
        feedback_parts.append("Simulation file found but not from this session (0 pts for sim).")
    else:
        feedback_parts.append("No simulation output found.")

    # 3. Verify System Parameters
    systems_data = result.get('systems', {})
    
    heat_source_correct_count = 0
    eir_correct_count = 0
    temp_correct_count = 0
    supp_correct_count = 0
    
    for sys_name in TARGET_SYSTEMS:
        sys_data = systems_data.get(sys_name)
        if not sys_data:
            feedback_parts.append(f"System {sys_name} not found in output.")
            continue
            
        # Check HEAT-SOURCE (6 pts)
        # Expected: "HEAT-PUMP"
        actual_hs = str(sys_data.get('heat_source', '')).upper()
        if actual_hs == "HEAT-PUMP":
            score += 6
            heat_source_correct_count += 1
        
        # Check HEATING-EIR (5 pts)
        # Expected: 0.30488 ± 0.005
        actual_eir = sys_data.get('heating_eir', -1.0)
        if 0.299 <= actual_eir <= 0.310:
            score += 5
            eir_correct_count += 1
            
        # Check MIN-HP-T (3 pts)
        # Expected: 17 ± 1.0
        actual_temp = sys_data.get('min_hp_t', -999.0)
        if 16.0 <= actual_temp <= 18.0:
            score += 3
            temp_correct_count += 1
            
        # Check HP-SUPP-SOURCE (4 pts)
        # Expected: "ELECTRIC"
        actual_supp = str(sys_data.get('hp_supp_source', '')).upper()
        if actual_supp == "ELECTRIC":
            score += 4
            supp_correct_count += 1

    # Add system feedback summaries
    if heat_source_correct_count == 5:
        feedback_parts.append("All 5 systems converted to HEAT-PUMP (+30).")
    else:
        feedback_parts.append(f"{heat_source_correct_count}/5 systems converted to HEAT-PUMP.")

    if eir_correct_count == 5:
        feedback_parts.append("All 5 systems EIR correct (+25).")
    else:
        feedback_parts.append(f"{eir_correct_count}/5 systems EIR correct.")
        
    if temp_correct_count < 5:
        feedback_parts.append(f"{temp_correct_count}/5 systems Min Temp correct.")
        
    if supp_correct_count < 5:
        feedback_parts.append(f"{supp_correct_count}/5 systems Supp Source correct.")

    # 4. Final Scoring Logic
    # Pass requirements:
    # 1. Score >= 60
    # 2. Simulation ran (sim_ran is True)
    # 3. At least 3/5 systems have HEAT-SOURCE = HEAT-PUMP (fundamental task achievement)
    
    passed = (score >= 60) and sim_ran and (heat_source_correct_count >= 3)
    
    if not sim_ran:
        feedback_parts.append("FAIL: Simulation did not run during session.")
        
    if heat_source_correct_count < 3:
        feedback_parts.append("FAIL: Fewer than 3 systems converted to Heat Pump.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }