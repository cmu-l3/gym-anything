#!/usr/bin/env python3
"""
Verifier for fenestration_upgrade_low_e@1 task.

Criteria:
1. Simulation ran during session (15 pts)
2. Project saved during session (5 pts)
3. ALL GLASS-TYPE objects updated:
   - GLASS-CONDUCTANCE = 0.29 +/- 0.01 (40 pts distributed)
   - SHADING-COEF = 0.40 +/- 0.01 (40 pts distributed)

The score for glass updates is distributed evenly across all found glass types.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILENAME = "task_result.json"
RESULT_PATH_WIN = r"C:\Users\Docker\task_result.json"

def verify_fenestration_upgrade_low_e(traj, env_info, task_info):
    """
    Verifies that all glass types in the eQUEST model were updated correctly
    and the simulation was run.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_WIN, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data. Did you save the project and run the simulation?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    sim_is_new = result.get('sim_file_is_new', False)
    project_saved = result.get('project_saved', False)
    glass_types = result.get('glass_types', [])
    
    score = 0
    feedback_parts = []
    
    # 3. Scoring - Operational (20 pts)
    if sim_is_new:
        score += 15
        feedback_parts.append("Simulation run confirmed (+15)")
    else:
        feedback_parts.append("Simulation NOT run or stale (+0)")
        
    if project_saved:
        score += 5
        feedback_parts.append("Project saved (+5)")
    else:
        feedback_parts.append("Project NOT saved (+0)")

    # 4. Scoring - Technical (80 pts)
    # Target values
    TARGET_COND = 0.29
    TARGET_SC = 0.40
    TOLERANCE = 0.01
    
    if not glass_types:
        feedback_parts.append("ERROR: No GLASS-TYPE definitions found in project file.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    num_glass = len(glass_types)
    pts_per_glass_prop = 40.0 / num_glass # 40 pts for Conductance, 40 pts for SC
    
    correct_cond_count = 0
    correct_sc_count = 0
    
    for gt in glass_types:
        name = gt.get('name', 'Unknown')
        cond = gt.get('conductance')
        sc = gt.get('shading_coef')
        
        # Verify Conductance
        if cond is not None and abs(float(cond) - TARGET_COND) <= TOLERANCE:
            score += pts_per_glass_prop
            correct_cond_count += 1
        else:
            val_str = f"{cond}" if cond is not None else "Missing"
            logger.info(f"Glass '{name}': Conductance {val_str} != {TARGET_COND}")

        # Verify Shading Coef
        if sc is not None and abs(float(sc) - TARGET_SC) <= TOLERANCE:
            score += pts_per_glass_prop
            correct_sc_count += 1
        else:
            val_str = f"{sc}" if sc is not None else "Missing"
            logger.info(f"Glass '{name}': SC {val_str} != {TARGET_SC}")

    # Generate Feedback
    if correct_cond_count == num_glass:
        feedback_parts.append("All U-factors correct (+40)")
    else:
        feedback_parts.append(f"{correct_cond_count}/{num_glass} U-factors correct")
        
    if correct_sc_count == num_glass:
        feedback_parts.append("All SC values correct (+40)")
    else:
        feedback_parts.append(f"{correct_sc_count}/{num_glass} SC values correct")

    # Round score
    score = round(score)
    
    # Pass logic: Must have run sim AND got a decent score (>=60)
    passed = (score >= 60) and sim_is_new
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }