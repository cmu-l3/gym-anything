#!/usr/bin/env python3
"""
Verifier for product_breakeven_simulator task.

Criteria:
1. File Saved & Fresh (15 pts)
2. Simulation Parameter Table (20 pts): 'Simulation_Units' or 'Generateseries' found
3. Measures Created (30 pts): Fixed_Cost (25000), Revenue, Total Cost
4. Velo Context (15 pts): 'Velo' string found in model (implies filtering)
5. Visuals (20 pts): Line Chart present

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_product_breakeven_simulator(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    # Note: Path must match what is in export_result.ps1
    vm_path = "C:/Users/Docker/Desktop/breakeven_result.json"
    
    try:
        copy_from_env(vm_path, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result file missing or invalid: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass

    score = 0
    feedback = []
    
    # 1. File Check (15 pts)
    if result.get('file_exists') and result.get('file_fresh'):
        score += 15
        feedback.append("File saved and new.")
    elif result.get('file_exists'):
        score += 5
        feedback.append("File saved but timestamp unverifiable.")
    else:
        feedback.append("File not saved.")
        return {"passed": False, "score": 0, "feedback": "File not found."}

    # Strings found in DataModel
    model_strings = set(result.get('model_strings', []))
    visual_types = result.get('visual_types', [])
    
    # 2. Simulation Parameter (20 pts)
    # Looking for 'Generateseries' (DAX for param) or 'Simulation_Units' (table name)
    if 'Generateseries' in model_strings or 'Simulation_Units' in model_strings:
        score += 20
        feedback.append("Simulation parameter table detected.")
    else:
        feedback.append("Simulation parameter table not found in model.")

    # 3. Measures (30 pts)
    measures_found = 0
    required_measures = ['Fixed_Cost', 'Simulated_Revenue', 'Total_Cost']
    for m in required_measures:
        if m in model_strings:
            measures_found += 1
            
    # Check for the constant 25000
    if '25000' in model_strings:
        measures_found += 1
        
    # Total 4 check items for 30 pts (approx 7.5 pts each)
    score += int((measures_found / 4) * 30)
    feedback.append(f"Measures check: {measures_found}/4 components found.")

    # 4. Velo Context (15 pts)
    if 'Velo' in model_strings:
        score += 15
        feedback.append("'Velo' product context found.")
    else:
        feedback.append("'Velo' product filter not detected in model strings.")

    # 5. Visuals (20 pts)
    # Expect lineChart
    if 'lineChart' in visual_types:
        score += 20
        feedback.append("Line chart visual present.")
    else:
        feedback.append("Line chart not found in layout.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }