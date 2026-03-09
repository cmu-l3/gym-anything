#!/usr/bin/env python3
"""
Verifier for infiltration_air_sealing_upgrade task.

Task:
1. Update AIR-CHANGES/HR to 0.25 for all 16 Perimeter spaces.
2. Leave Core spaces unchanged (typically default ~0.4-0.6 or different).
3. Run simulation.

Scoring (100 pts):
- Simulation run during session: 10 pts
- Perimeter spaces correct: 5 pts each * 16 spaces = 80 pts
- Core spaces intact: 2.5 pts each * 4 spaces = 10 pts
- Pass threshold: >= 60 pts AND simulation run.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILENAME = "infiltration_result.json"
TARGET_INFILTRATION = 0.25
TOLERANCE = 0.02

def verify_infiltration_air_sealing_upgrade(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path inside container (Windows path mapped to standard location logic in export script)
        # The export script saved to C:\Users\Docker\infiltration_result.json
        copy_from_env("C:\\Users\\Docker\\infiltration_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not retrieve task result. Did you run the simulation and save the project?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Score Simulation (10 pts)
    sim_new = result.get('sim_file_new', False)
    if sim_new:
        score += 10
        feedback_parts.append("Simulation run successfully (+10).")
    else:
        feedback_parts.append("Simulation NOT run during task (0/10).")

    # 3. Score Spaces
    spaces = result.get('spaces', [])
    perimeter_correct_count = 0
    core_intact_count = 0
    perimeter_total = 0
    core_total = 0
    
    # We expect 16 perimeter and 4 core in 4StoreyBuilding
    # But we calculate based on what was found to handle model variations gracefully
    
    for sp in spaces:
        s_name = sp.get('name', 'Unknown')
        s_type = sp.get('type', 'Unknown')
        val = sp.get('infiltration', -1)
        
        if s_type == 'Perimeter':
            perimeter_total += 1
            if abs(val - TARGET_INFILTRATION) <= TOLERANCE:
                perimeter_correct_count += 1
            else:
                logger.info(f"Perimeter Space {s_name} incorrect: {val}")
                
        elif s_type == 'Core':
            core_total += 1
            # Core should NOT be 0.25 (unless it was already 0.25, but usually it's different)
            # A strict check would compare to baseline, but checking if it equals target 
            # is a good proxy for "did they accidentally bulk edit everything?"
            # If they deliberately set core to 0.25, that's wrong instructions.
            # If they left it alone, it likely != 0.25.
            # However, if the baseline IS 0.25, we can't penalize. 
            # In 4Storey, Core usually has very low infiltration or specific value.
            # We assume "Intact" means "Not changed to Target".
            # Better check: If they bulk applied, Core would equal Target.
            if abs(val - TARGET_INFILTRATION) > TOLERANCE:
                core_intact_count += 1
            else:
                # Ambiguous case: Did they set it, or was it already?
                # In this specific task, if Core == 0.25, we assume they bulk edited incorrectly.
                pass

    # Points Calculation
    # 16 Perimeter spaces * 5 pts = 80
    # 4 Core spaces * 2.5 pts = 10
    
    # Normalize if counts differ (e.g. if parser misses some)
    # We cap at max expected points
    
    p_score = perimeter_correct_count * 5
    c_score = core_intact_count * 2.5
    
    score += p_score
    score += c_score
    
    feedback_parts.append(f"Perimeter Spaces Correct: {perimeter_correct_count}/{perimeter_total} (+{p_score}).")
    feedback_parts.append(f"Core Spaces Unchanged: {core_intact_count}/{core_total} (+{c_score}).")

    if perimeter_correct_count < 12:
         feedback_parts.append("Warning: Too many perimeter spaces missed.")
         
    if core_intact_count < core_total:
         feedback_parts.append("Warning: Core spaces appear modified (bulk edit detected?).")

    # 4. Final Verification
    # Pass if Score >= 60 AND Simulation Ran
    passed = (score >= 60) and sim_new
    
    # Anti-gaming: If they didn't run sim, max score is capped at 50
    if not sim_new and score > 50:
        score = 50
        feedback_parts.append("Score capped at 50 because simulation was not run.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }