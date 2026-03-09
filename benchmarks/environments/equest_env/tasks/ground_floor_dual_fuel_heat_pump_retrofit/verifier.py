#!/usr/bin/env python3
"""
Verifier for ground_floor_dual_fuel_heat_pump_retrofit task.

Task Requirements:
1.  All 5 Ground Floor (G.*) systems must be updated.
2.  HEAT-SOURCE = HEAT-PUMP
3.  SUPPL-HEAT-SOURCE = FURNACE
4.  MIN-HP-T = 35 (Switchover temp)
5.  Simulation must be run (creating a new .SIM file).

Scoring (100 pts total):
- Simulation Ran: 10 pts
- Heat Source = Heat Pump: 25 pts (5 pts per system)
- Suppl Source = Furnace: 25 pts (5 pts per system)
- Switchover Temp = 35: 40 pts (8 pts per system)

Pass Threshold: 60 pts AND Simulation Ran.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# This path matches the one defined in export_result.ps1
RESULT_PATH = "C:\\Users\\Docker\\ground_floor_dual_fuel_heat_pump_retrofit_result.json"

def verify_ground_floor_dual_fuel_heat_pump_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification interface not available (copy_from_env missing)"}

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results. Did you save the project?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Simulation (10 pts)
    sim_run = result.get('sim_file_is_new', False)
    if sim_run:
        score += 10
        feedback.append("Simulation run confirmed (+10).")
    else:
        feedback.append("Simulation NOT run (0/10).")

    # 2. Check Systems Configuration
    systems = result.get('systems_data', [])
    g_systems_count = len(systems)
    
    if g_systems_count == 0:
        feedback.append("No Ground Floor systems found in project file.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Track sub-scores
    heat_source_score = 0
    suppl_source_score = 0
    switchover_score = 0
    
    # Target Values
    TARGET_HEAT_SOURCE = "HEAT-PUMP"
    TARGET_SUPPL_SOURCE = "FURNACE"
    TARGET_MIN_HP_T = 35.0
    
    correct_heat_source_count = 0
    correct_suppl_source_count = 0
    correct_min_t_count = 0

    for sys in systems:
        name = sys.get('name', 'Unknown')
        
        # Check Heat Source (5 pts each)
        hs = sys.get('heat_source', '').upper()
        if hs == TARGET_HEAT_SOURCE:
            heat_source_score += 5
            correct_heat_source_count += 1
        
        # Check Supplemental Source (5 pts each)
        ss = sys.get('suppl_source', '').upper()
        if ss == TARGET_SUPPL_SOURCE:
            suppl_source_score += 5
            correct_suppl_source_count += 1
            
        # Check Min HP Temp (8 pts each)
        try:
            mt = float(sys.get('min_hp_t', -1))
            if abs(mt - TARGET_MIN_HP_T) < 0.5:
                switchover_score += 8
                correct_min_t_count += 1
        except ValueError:
            pass

    # Cap scores (in case agent creates duplicate systems)
    heat_source_score = min(25, heat_source_score)
    suppl_source_score = min(25, suppl_source_score)
    switchover_score = min(40, switchover_score)
    
    score += heat_source_score + suppl_source_score + switchover_score
    
    # Feedback generation
    feedback.append(f"Heat Source: {correct_heat_source_count}/5 systems correct (+{heat_source_score}).")
    feedback.append(f"Supplemental Source: {correct_suppl_source_count}/5 systems correct (+{suppl_source_score}).")
    feedback.append(f"Switchover Temp: {correct_min_t_count}/5 systems correct (+{switchover_score}).")

    if correct_suppl_source_count < 5 and correct_heat_source_count > 0:
        feedback.append("Tip: Ensure 'Supplemental Heat Source' is set to 'Furnace' (Dual Fuel), not default/Electric.")

    # Final Pass/Fail Logic
    passed = (score >= 60) and sim_run
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }