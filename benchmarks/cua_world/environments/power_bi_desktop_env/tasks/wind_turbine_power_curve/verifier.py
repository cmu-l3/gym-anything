#!/usr/bin/env python3
"""
Verifier for wind_turbine_power_curve task.

Scoring (100 points total):
1. File Saved (10 pts): .pbix exists and modified.
2. Data Loaded (10 pts): Data loaded (inferred from model size/structure).
3. Modeling (40 pts):
   - 'Wind_Bin' Calculated Column exists (20 pts).
   - 'Avg_Power' Measure exists (20 pts).
4. Visualization (25 pts):
   - Line Chart exists (15 pts).
   - Scatter Chart exists (10 pts).
5. Logic/Filtering (15 pts):
   - Evidence of filtering on Status_Code (15 pts).

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wind_turbine_power_curve(traj, env_info, task_info):
    # Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Retrieve result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        # PBI environment uses Windows paths in VM, but we copy to local temp
        copy_from_env("C:/Users/Docker/Desktop/task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Saved (10 pts)
    if result.get('file_exists', False) and result.get('file_modified', False):
        score += 10
        feedback.append("Report file saved and modified.")
    elif result.get('file_exists', False):
        score += 5
        feedback.append("Report file exists but was not modified (anti-gaming warning).")
    else:
        feedback.append("Report file not found.")

    # 2. Data Loaded (10 pts)
    # We infer this if the file size is reasonable (>10KB) or measures/columns are found
    if result.get('file_size_bytes', 0) > 10000:
        score += 10
        feedback.append("Data import likely successful (file size check).")
    else:
        feedback.append("File size too small, data likely not loaded.")

    # 3. Modeling (40 pts)
    measures = result.get('measures_found', [])
    columns = result.get('columns_found', [])
    
    if "Wind_Bin" in columns:
        score += 20
        feedback.append("Calculated Column 'Wind_Bin' found.")
    else:
        feedback.append("Calculated Column 'Wind_Bin' NOT found.")
        
    if "Avg_Power" in measures:
        score += 20
        feedback.append("DAX Measure 'Avg_Power' found.")
    else:
        feedback.append("DAX Measure 'Avg_Power' NOT found.")

    # 4. Visualization (25 pts)
    visuals = result.get('visual_types', [])
    
    if "lineChart" in visuals:
        score += 15
        feedback.append("Line Chart found (Power Curve).")
    else:
        feedback.append("Line Chart NOT found.")
        
    if "scatterChart" in visuals:
        score += 10
        feedback.append("Scatter Chart found (Raw Data).")
    else:
        feedback.append("Scatter Chart NOT found.")

    # 5. Logic/Filtering (15 pts)
    # The export script checks for "Status_Code" in the layout JSON, which implies usage
    if result.get('filters_likely', False):
        score += 15
        feedback.append("Filtering logic detected (Status_Code used in report).")
    else:
        feedback.append("No evidence of filtering by 'Status_Code'.")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }