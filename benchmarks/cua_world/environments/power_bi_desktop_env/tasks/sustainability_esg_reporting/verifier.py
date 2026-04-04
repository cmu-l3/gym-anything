#!/usr/bin/env python3
"""
Verifier for sustainability_esg_reporting task.

Scoring (100 points total):
1. PBIX File Saved (10 pts)
2. Anti-Gaming (Timestamp check) (10 pts)
3. Data Model Measures (30 pts): 'Total_Emissions', 'Emissions_kg'
4. Visuals (30 pts): Matrix (pivotTable) and Card present
5. VLM Verification (20 pts): Confirms visual appearance
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory for shared utilities if needed
sys.path.insert(0, str(Path(__file__).parent.parent))
from gym_anything.vlm import query_vlm, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_sustainability_esg_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/esg_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. File Check (20 pts)
    if result.get('file_exists'):
        score += 10
        feedback.append("ESG_Report.pbix exists.")
        if result.get('file_created_during_task'):
            score += 10
            feedback.append("File created during task session.")
        else:
            feedback.append("WARNING: File timestamp predates task.")
    else:
        feedback.append("ESG_Report.pbix not found.")

    # 3. Data Model Check (30 pts)
    measures = result.get('measures_found', [])
    if 'Total_Emissions' in measures:
        score += 15
        feedback.append("Measure 'Total_Emissions' found.")
    else:
        feedback.append("Measure 'Total_Emissions' missing.")
        
    if 'Emissions_kg' in measures:
        score += 15
        feedback.append("Column/Measure 'Emissions_kg' found.")
    else:
        feedback.append("Column/Measure 'Emissions_kg' missing.")

    # 4. Visuals Check (30 pts)
    visuals = result.get('visuals_found', [])
    if 'pivotTable' in visuals: # Matrix is pivotTable in Layout JSON
        score += 15
        feedback.append("Matrix visual found.")
    else:
        feedback.append("Matrix visual missing.")
        
    if 'card' in visuals:
        score += 15
        feedback.append("Card visual found.")
    else:
        feedback.append("Card visual missing.")

    # 5. VLM Verification (20 pts)
    # Check if the matrix looks populated and hierarchical
    final_img = get_final_screenshot(traj)
    vlm_score = 0
    if final_img:
        prompt = """
        Analyze this Power BI report. 
        1. Is there a Matrix/Table visual showing data? 
        2. Does it appear to have a hierarchy (e.g. Region expandable to Fuel Type)?
        3. Is there a Card visual with a number?
        """
        vlm_res = query_vlm(prompt, final_img)
        if vlm_res.get("success"):
            analysis = vlm_res.get("parsed", {}) # Assuming structured output or generic
            # Fallback simple text check if structured not enforced
            text = vlm_res.get("text", "").lower()
            if "matrix" in text or "table" in text: vlm_score += 10
            if "card" in text or "number" in text: vlm_score += 10
            feedback.append(f"VLM Analysis: {text[:50]}...")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }