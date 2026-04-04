#!/usr/bin/env python3
"""
Verifier for facility_wide_ducted_return_retrofit task.

The agent must:
1. Update all 15 PSZ systems (G.*, M.*, T.*) with:
   - RETURN-AIR-PATH = DUCTED
   - RETURN-STATIC = 0.75
2. Run the annual simulation (creating a fresh .SIM file)
3. Save the project

Scoring (100 points total):
- Simulation Ran: 10 pts (fresh .SIM file)
- Ground Floor Updates: 30 pts (5 systems x 6 pts)
- Middle Floor Updates: 30 pts (5 systems x 6 pts)
- Top Floor Updates: 30 pts (5 systems x 6 pts)
  * Per system: 3 pts for Path, 3 pts for Static

Pass Threshold: >= 60 points AND Simulation Ran.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH_CONTAINER = "C:\\tmp\\task_result.json"

def verify_facility_wide_ducted_return_retrofit(traj, env_info, task_info):
    """
    Verify that all 15 systems were updated to Ducted Return with 0.75 static
    and simulation was run.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_CONTAINER, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    sim_ran = result.get("sim_file_is_new", False)
    systems_data = result.get("systems_data", {})
    
    score = 0
    feedback = []
    
    # 3. Score Simulation (10 pts)
    if sim_ran:
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation NOT run or results stale (0/10).")

    # 4. Score Systems
    floors = {'G': 'Ground', 'M': 'Middle', 'T': 'Top'}
    floor_scores = {'G': 0, 'M': 0, 'T': 0}
    
    # Iterate through expected 15 systems
    # We construct expected names based on knowledge of 4StoreyBuilding or check loaded data
    # The export script filters for keys starting with G., M., T.
    
    total_correct_path = 0
    total_correct_static = 0
    
    for sys_name, data in systems_data.items():
        # Identify floor prefix
        prefix = sys_name[0] if sys_name and len(sys_name) > 0 else None
        if prefix not in floors:
            continue
            
        sys_path = data.get("RETURN-AIR-PATH", "").upper()
        sys_static = data.get("RETURN-STATIC", 0.0)
        
        pts = 0
        sys_feedback = []
        
        # Check Path (3 pts)
        if sys_path == "DUCTED":
            pts += 3
            total_correct_path += 1
        
        # Check Static (3 pts)
        # Allow small tolerance for float comparison
        if abs(sys_static - 0.75) < 0.01:
            pts += 3
            total_correct_static += 1
            
        floor_scores[prefix] += pts

    # Add to total score
    score += floor_scores['G']
    score += floor_scores['M']
    score += floor_scores['T']
    
    # Generate Feedback
    for f_code, f_name in floors.items():
        f_score = floor_scores[f_code]
        if f_score == 30:
            feedback.append(f"{f_name} Floor: All systems correct (+30).")
        else:
            feedback.append(f"{f_name} Floor: Partial success ({f_score}/30).")

    # 5. Final Assessment
    passed = (score >= 60) and sim_ran
    
    final_feedback = " | ".join(feedback)
    if not sim_ran:
        final_feedback += " | FAIL: Simulation run required to pass."
        
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback,
        "details": {
            "correct_paths": total_correct_path,
            "correct_static_pressure": total_correct_static,
            "sim_ran": sim_ran
        }
    }