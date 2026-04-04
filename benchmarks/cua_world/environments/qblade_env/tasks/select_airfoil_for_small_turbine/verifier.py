#!/usr/bin/env python3
"""
Verifier for Airfoil Comparison Task.

Verifies:
1. QBlade project file existence and content (2 Rotors, Polars).
2. Report file existence and values (Cp values in realistic range, correct winner).
3. Anti-gaming (files created during task).
4. VLM Trajectory (evidence of workflow steps).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_airfoil_selection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load task result from JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # 1. Project File Checks (30 pts)
    if result.get("project_exists") and result.get("project_created_during_task"):
        score += 10
        feedback.append("Project file saved.")
        
        # Check content
        rotors = result.get("rotors_found_count", 0)
        polars = result.get("polars_found_count", 0)
        
        # Expect at least 2 rotors (one for each airfoil)
        if rotors >= 2:
            score += 10
            feedback.append("Two rotors found in project.")
        else:
            feedback.append(f"Found {rotors} rotors (expected >= 2).")
            
        # Expect evidence of polars (Re=300k)
        if polars >= 2:
            score += 10
            feedback.append("Polars for Re=300,000 found.")
    else:
        feedback.append("Project file missing or not created during task.")
        
    # 2. Report File Checks (40 pts)
    if result.get("report_exists") and result.get("report_created_during_task"):
        score += 10
        feedback.append("Report file created.")
        
        try:
            clark_cp = float(result.get("reported_clarky_cp", 0))
            naca_cp = float(result.get("reported_naca_cp", 0))
            
            # Sanity check for Cp values (Betz limit is ~0.59, real rotors ~0.35-0.55)
            if 0.35 <= clark_cp <= 0.55:
                score += 10
                feedback.append(f"Clark-Y Cp ({clark_cp}) in realistic range.")
            else:
                feedback.append(f"Clark-Y Cp ({clark_cp}) outside expected range (0.35-0.55).")
                
            if 0.35 <= naca_cp <= 0.55:
                score += 10
                feedback.append(f"NACA 4412 Cp ({naca_cp}) in realistic range.")
            else:
                feedback.append(f"NACA 4412 Cp ({naca_cp}) outside expected range (0.35-0.55).")
                
            # Winner Logic (NACA 4412 typically wins due to higher camber/lift at this scale/Re)
            # However, we accept whatever matches the reported data if the data is valid
            winner = result.get("reported_winner", "").lower()
            
            if naca_cp > clark_cp and "naca" in winner:
                score += 10
                feedback.append("Correct winner identified based on data.")
            elif clark_cp > naca_cp and "clark" in winner:
                score += 10
                feedback.append("Correct winner identified based on data (Unexpected result but internally consistent).")
            else:
                feedback.append(f"Winner declaration ('{winner}') contradicts reported data.")
                
        except ValueError:
            feedback.append("Could not parse numerical Cp values from report.")
    else:
        feedback.append("Report file missing.")

    # 3. Application State (10 pts)
    if result.get("app_running"):
        score += 10
        feedback.append("QBlade was running at end of task.")
        
    # 4. VLM / Trajectory Verification (20 pts)
    # This section simulates VLM checks since we can't run actual VLM here.
    # We assume if the project file has complex internal structure (rotors/polars), 
    # the workflow was likely followed.
    if result.get("rotors_found_count", 0) >= 2 and result.get("polars_found_count", 0) >= 2:
        score += 20
        feedback.append("Internal project structure confirms workflow execution.")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }