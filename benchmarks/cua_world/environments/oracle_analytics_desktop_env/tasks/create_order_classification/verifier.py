#!/usr/bin/env python3
"""
Verifier for create_order_classification task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_order_classification(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the creation of an order classification calculated column and donut chart.
    
    Verification Signals:
    1. Primary: JSON result from Windows guest (via export_result.ps1)
       - Checks if .dva file exists and was created during task
       - Checks content of .dva (xml/json) for "Order Size Tier" and CASE logic
       - Checks for Donut chart definition
    2. Secondary: VLM on trajectory (optional but good for visual confirmation)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: export_result.ps1 saves to C:\Windows\Temp\task_result.json
        # Docker/Env path mapping handles the path conversion usually, 
        # but if we need the absolute path inside the container:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not retrieve task verification data. Did the agent save the file?"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: Output File Exists (15 pts)
    if result_data.get("output_exists", False):
        score += 15
        feedback.append("Workbook file 'Order_Size_Analysis.dva' found.")
    else:
        feedback.append("Workbook file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Anti-Gaming / Freshness (15 pts)
    if result_data.get("file_created_during_task", False):
        score += 15
        feedback.append("File was created during the task session.")
    else:
        feedback.append("File timestamp indicates it was not created during this session.")
        # We penalize but continue checking content

    # Criterion 3: Content Verification (70 pts)
    validation = result_data.get("validation", {})
    
    # 3a. Calculated Column Name (15 pts)
    if validation.get("has_calc_name", False):
        score += 15
        feedback.append("Calculated column 'Order Size Tier' found.")
    else:
        feedback.append("Calculated column name not found in workbook data.")

    # 3b. CASE Logic (20 pts)
    if validation.get("has_case_logic", False):
        score += 20
        feedback.append("Conditional (CASE) logic detected.")
    else:
        feedback.append("CASE logic not detected in workbook.")

    # 3c. Categories (10 pts)
    if validation.get("has_categories", False):
        score += 10
        feedback.append("Categories (Small, Medium, Enterprise) found.")
    else:
        feedback.append("Expected category labels not found.")

    # 3d. Chart Type (10 pts)
    if validation.get("has_donut_chart", False):
        score += 10
        feedback.append("Donut/Pie chart visualization detected.")
    else:
        feedback.append("Visualization type check failed (expected Donut/Pie).")

    # VLM Check (Optional integration)
    # If we had VLM integration here, we would add points for visual confirmation.
    # For now, we rely on the robust file parsing.
    
    # Final Pass Determination
    # Threshold: 65 points (Needs File + Created + Calc Name + Logic)
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }