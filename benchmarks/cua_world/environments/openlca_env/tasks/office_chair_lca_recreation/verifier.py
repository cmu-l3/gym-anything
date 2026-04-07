#!/usr/bin/env python3
"""
Verifier for Office Chair LCA Recreation task.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_office_chair_lca(traj, env_info, task_info):
    """
    Verifies the Office Chair LCA task.
    
    Criteria:
    1. Process 'Office Chair Assembly' created in DB (20 pts)
    2. Process has at least 4 input exchanges (Steel, Al, Nylon, PP, Transport) (20 pts)
    3. Result CSV file exists and contains 'Global Warming' data (20 pts)
    4. Verdict text file exists and contains a numeric value (20 pts)
    5. VLM Trajectory shows material search/selection (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load programmatic result
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
            
    # Load output files for content check
    csv_content = ""
    try:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env("/home/ga/LCA_Results/chair_impact.csv", temp_csv.name)
        with open(temp_csv.name, 'r', errors='ignore') as f:
            csv_content = f.read()
        os.unlink(temp_csv.name)
    except:
        pass # File might not exist

    score = 0
    feedback = []
    
    # 1. Process Created (20 pts)
    if result.get("process_found"):
        score += 20
        feedback.append("Process 'Office Chair Assembly' found in database.")
    else:
        feedback.append("Process 'Office Chair Assembly' NOT found in database.")
        
    # 2. Inputs Added (20 pts)
    # Expecting 5 inputs (Steel, Al, Nylon, PP, Transport)
    # Allow partial credit for partial inputs
    input_count = result.get("input_count", 0)
    if input_count >= 5:
        score += 20
        feedback.append(f"Correct number of inputs found ({input_count}).")
    elif input_count >= 3:
        score += 10
        feedback.append(f"Some inputs found ({input_count}), but fewer than expected (5).")
    else:
        feedback.append(f"Insufficient inputs found ({input_count}).")
        
    # 3. Calculation Run / CSV (20 pts)
    if result.get("csv_exists"):
        # Check content
        if "Global Warming" in csv_content or "GWP" in csv_content:
            score += 20
            feedback.append("LCIA results exported successfully with GWP data.")
        else:
            score += 10
            feedback.append("Result file exists but GWP category not detected.")
    else:
        feedback.append("Impact result CSV not found.")
        
    # 4. Verdict Reported (20 pts)
    verdict_content = result.get("verdict_content", "")
    # Look for a number in the text (e.g., "52.3 kg", "48")
    # Simple regex for a float number
    found_number = re.search(r'\d+(\.\d+)?', verdict_content)
    
    if result.get("verdict_exists"):
        if found_number:
            score += 20
            feedback.append(f"Verdict file reported value: {found_number.group(0)}")
        else:
            score += 10
            feedback.append("Verdict file exists but no numeric value found.")
    else:
        feedback.append("Verdict/Verdict text file not found.")

    # 5. VLM Verification (20 pts)
    # (Placeholder logic - would use actual VLM in full system)
    # For now, we assume if they made the process and exported results, they did the work.
    # In a real VLM call, we'd check for "Material Search" dialogs.
    if score >= 60: 
        score += 20
        feedback.append("Workflow implied by successful output.")
    else:
        feedback.append("Workflow incomplete.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }