#!/usr/bin/env python3
"""
Verifier for hourly_report_zone_comfort_analysis task.

Task:
1. Create HOURLY-REPORT named "ComfortCheck".
2. Include AMBIENT-T (Global).
3. Include ZONE-T (Space) for T.S31.
4. Run simulation.

Scoring:
- Simulation ran during session: 10 pts
- Report 'ComfortCheck' defined: 20 pts
- AMBIENT-T included: 20 pts
- ZONE-T included: 20 pts
- T.S31 selected correctly: 15 pts
- Output Valid (implied by configuration + sim run): 15 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILENAME = "task_result.json"
RESULT_PATH_WIN = "C:\\Users\\Docker\\task_result.json"

def verify_hourly_report(traj, env_info, task_info):
    """
    Verify the hourly report configuration and simulation execution.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_WIN, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task results. Did the task complete successfully?"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Report Definition (20 pts)
    if result.get('report_defined', False) and result.get('report_name_correct', False):
        score += 20
        feedback_parts.append("Report 'ComfortCheck' defined (+20)")
    else:
        feedback_parts.append("Report 'ComfortCheck' NOT found in project")

    # Criterion 2: Variables (40 pts)
    if result.get('ambient_var_found', False):
        score += 20
        feedback_parts.append("AMBIENT-T included (+20)")
    else:
        feedback_parts.append("AMBIENT-T missing")
        
    if result.get('zone_var_found', False):
        score += 20
        feedback_parts.append("ZONE-T included (+20)")
    else:
        feedback_parts.append("ZONE-T missing")

    # Criterion 3: Space Selection (15 pts)
    if result.get('target_zone_correct', False):
        score += 15
        feedback_parts.append("Target space T.S31 correct (+15)")
    else:
        feedback_parts.append("Target space T.S31 NOT selected")

    # Criterion 4: Simulation Execution (25 pts total - split for robustness)
    # 10 pts for running, 15 pts for valid output (implied by valid config + run)
    sim_run = result.get('sim_new', False)
    if sim_run:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
        
        # If config is good AND sim ran, we assume output is valid
        if score >= 85: # 20+20+20+15+10 = 85 so far
            score += 15
            feedback_parts.append("Output data generated (+15)")
        else:
            feedback_parts.append("Output generated but configuration incorrect (0 pts for validity)")
    else:
        feedback_parts.append("Simulation did NOT run during task")

    passed = (score >= 60) and sim_run
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }