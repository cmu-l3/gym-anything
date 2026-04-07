#!/usr/bin/env python3
"""Verifier for analyze_pv_seasonality_index task.

Copies the agent's output JSON and independently verifies the math based on their extracted monthly array.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_seasonality_index(traj, env_info, task_info):
    """Verify the seasonality analysis was completed successfully.
    
    Scoring: 100 points max
    - File Existence & Timestamp: 20 points
    - Physical Realism (Annual Energy bounds): 20 points
    - Monthly Data Extraction (Array size & format): 20 points
    - Seasonality Index Math (Cross-checked): 20 points
    - Summer Percentage Math (Cross-checked): 20 points
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/SAM_Projects/seasonality_report.json')
    expected_annual_min = metadata.get('expected_annual_kwh_min', 32000000)
    expected_annual_max = metadata.get('expected_annual_kwh_max', 40000000)

    score = 0
    feedback_parts = []
    
    # 1. Read export wrapper JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_stats = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task stats: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check File Existence & Timestamp
    file_exists = export_stats.get('file_exists', False)
    file_modified = export_stats.get('file_modified', False)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Output file seasonality_report.json not found."}
    
    if file_modified:
        score += 20
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File exists but timestamp indicates it was not created during task")

    # 2. Read actual output JSON
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(expected_output_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse seasonality_report.json: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Check Physical Realism (Annual Energy)
    annual_kwh = report_data.get('annual_energy_kwh', 0)
    if isinstance(annual_kwh, (int, float)) and expected_annual_min <= annual_kwh <= expected_annual_max:
        score += 20
        feedback_parts.append(f"Annual energy realistic ({annual_kwh:,.0f} kWh)")
    else:
        feedback_parts.append(f"Annual energy {annual_kwh} out of expected bounds ({expected_annual_min}-{expected_annual_max})")

    # Check Monthly Data Extraction
    monthly_array = report_data.get('monthly_energy_kwh', [])
    if isinstance(monthly_array, list) and len(monthly_array) == 12 and all(isinstance(x, (int, float)) for x in monthly_array):
        score += 20
        feedback_parts.append("12-month array correctly extracted")
    else:
        feedback_parts.append("monthly_energy_kwh missing or invalid format")
        # Cannot calculate downstream metrics without valid array
        passed = score >= 80
        return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}

    # Recalculate values for cross-checking
    min_month = min(monthly_array)
    max_month = max(monthly_array)
    
    if min_month <= 0:
        feedback_parts.append("Invalid minimum monthly energy (<= 0)")
        true_seasonality = 0
    else:
        true_seasonality = max_month / min_month
        
    true_summer_sum = sum(monthly_array[5:8]) # June (index 5), July (6), August (7)
    
    # Depending on whether they used the sum of the array or the explicit annual energy
    true_summer_pct_arr = (true_summer_sum / sum(monthly_array)) * 100 if sum(monthly_array) > 0 else 0
    true_summer_pct_ann = (true_summer_sum / annual_kwh) * 100 if annual_kwh > 0 else 0

    # Verify Agent's Seasonality Index
    agent_seasonality = report_data.get('seasonality_index', -1)
    if isinstance(agent_seasonality, (int, float)) and true_seasonality > 0:
        if math.isclose(agent_seasonality, true_seasonality, rel_tol=0.02):
            score += 20
            feedback_parts.append(f"Seasonality Index correct ({agent_seasonality:.2f})")
        else:
            feedback_parts.append(f"Seasonality Index wrong (got {agent_seasonality}, expected ~{true_seasonality:.2f})")
    else:
        feedback_parts.append("Seasonality index missing or invalid")

    # Verify Agent's Summer Percentage
    agent_summer_pct = report_data.get('summer_generation_percentage', -1)
    if isinstance(agent_summer_pct, (int, float)):
        if math.isclose(agent_summer_pct, true_summer_pct_arr, rel_tol=0.02) or \
           math.isclose(agent_summer_pct, true_summer_pct_ann, rel_tol=0.02):
            score += 20
            feedback_parts.append(f"Summer Percentage correct ({agent_summer_pct:.1f}%)")
        else:
            feedback_parts.append(f"Summer Pct wrong (got {agent_summer_pct}, expected ~{true_summer_pct_arr:.1f})")
    else:
        feedback_parts.append("Summer generation percentage missing or invalid")

    # Final evaluation
    key_criteria_met = file_modified and len(monthly_array) == 12
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }