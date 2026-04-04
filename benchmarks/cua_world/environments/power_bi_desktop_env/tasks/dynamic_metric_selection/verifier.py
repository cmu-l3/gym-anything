#!/usr/bin/env python3
"""
Verifier for dynamic_metric_selection task.

Scoring (100 points total):
1. File Saved (10 pts) - Anti-gaming: must be modified during task.
2. Selection Table (15 pts) - 'Metric_Param' exists.
3. Base Measures (15 pts) - Revenue, Units, Transactions measures exist.
4. Dynamic Logic (25 pts) - Measure with SWITCH and SELECTEDVALUE.
5. Dynamic Title (15 pts) - 'Chart_Title' measure exists.
6. Visuals (20 pts) - Slicer and Bar Chart present in layout.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_dynamic_metric_selection(traj, env_info, task_info):
    """Verify that the agent implemented the dynamic metric selector pattern."""
    
    # 1. Retrieve Result JSON from Environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing."}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/dynamic_metric_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Criteria
    
    # Criterion 1: File Validity (10 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 10
        feedback_parts.append("Report saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("Report exists but timestamp verification failed.")
    else:
        feedback_parts.append("Report file not found.")

    # Criterion 2: Selection Table (15 pts)
    tables = result.get('tables_found', [])
    if "Metric_Param" in tables:
        score += 15
        feedback_parts.append("Parameter table found.")
    else:
        feedback_parts.append("Metric_Param table missing.")

    # Criterion 3: Base Measures (15 pts)
    measures = result.get('measures_found', [])
    base_measures = ["Total_Revenue", "Total_Units", "Total_Transactions"]
    found_base = [m for m in base_measures if m in measures]
    
    if len(found_base) == 3:
        score += 15
        feedback_parts.append("All base measures found.")
    elif len(found_base) > 0:
        partial = 5 * len(found_base)
        score += partial
        feedback_parts.append(f"Some base measures found ({len(found_base)}/3).")
    else:
        feedback_parts.append("Base measures missing.")

    # Criterion 4: Dynamic Logic (25 pts)
    # Check for the main dynamic measure AND the logic keywords
    has_dynamic_measure = "Selected_Metric_Value" in measures
    has_switch = result.get('switch_logic_found', False)
    has_sel_val = result.get('selectedvalue_found', False)

    if has_dynamic_measure:
        score += 10
        if has_switch and has_sel_val:
            score += 15
            feedback_parts.append("Dynamic measure logic (SWITCH/SELECTEDVALUE) verified.")
        else:
            feedback_parts.append("Dynamic measure name found, but internal logic (SWITCH) unclear.")
    else:
        feedback_parts.append("Measure 'Selected_Metric_Value' not found.")

    # Criterion 5: Dynamic Title (15 pts)
    if "Chart_Title" in measures:
        score += 15
        feedback_parts.append("Dynamic title measure found.")
    else:
        feedback_parts.append("Chart_Title measure missing.")

    # Criterion 6: Visuals (20 pts)
    has_slicer = result.get('slicer_found', False)
    has_chart = result.get('bar_chart_found', False)
    
    if has_slicer: score += 10
    if has_chart: score += 10
    
    if has_slicer and has_chart:
        feedback_parts.append("Visuals (Slicer + Bar Chart) confirmed.")
    elif has_slicer or has_chart:
        feedback_parts.append("Missing one or more visuals.")

    # 3. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }