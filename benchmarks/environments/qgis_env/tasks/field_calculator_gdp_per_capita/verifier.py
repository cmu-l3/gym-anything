#!/usr/bin/env python3
"""
Verifier for field_calculator_gdp_per_capita task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_field_calculator_gdp_per_capita(traj, env_info, task_info):
    """
    Verify that the GDP per capita was calculated correctly and exported.
    
    Scoring Criteria:
    1. CSV File Exists (15 pts)
    2. File created/modified during task (15 pts) - Anti-gaming
    3. Valid CSV structure with headers (10 pts)
    4. Row count sufficiency (> 100 rows) (10 pts)
    5. 'gdp_per_capita' field exists (20 pts)
    6. Values are numeric and valid (15 pts)
    7. Values are plausible (calculation likely correct) (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. File Exists
    if result.get("file_exists"):
        score += 15
        feedback_parts.append("CSV file found.")
    else:
        feedback_parts.append("CSV file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Anti-gaming timestamp check
    if result.get("created_during_task"):
        score += 15
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File timestamp pre-dates task (anti-gaming fail).")

    # 3. Valid CSV
    if result.get("is_valid_csv"):
        score += 10
        feedback_parts.append("Valid CSV format.")
    else:
        feedback_parts.append("Invalid CSV structure.")

    # 4. Row Count
    rows = result.get("row_count", 0)
    if rows > 100:
        score += 10
        feedback_parts.append(f"Row count sufficient ({rows}).")
    else:
        feedback_parts.append(f"Row count too low ({rows}).")

    # 5. Field Exists
    if result.get("has_gdp_field"):
        score += 20
        feedback_parts.append("GDP per capita field found.")
    else:
        feedback_parts.append("GDP per capita field NOT found.")
        
    # 6. Numeric Values
    numeric_count = result.get("numeric_values_count", 0)
    if numeric_count > 100:
        score += 15
        feedback_parts.append("Values are numeric.")
    else:
        feedback_parts.append("Values are not numeric or missing.")

    # 7. Plausible Values (Calculation Check)
    # The formula implies a range. If they just put '1' everywhere, this fails.
    plausible = result.get("plausible_values_count", 0)
    distinct = result.get("distinct_values_count", 0)
    
    # We expect distinct values (calculation implies variance)
    if distinct > 20 and plausible > 50:
        score += 15
        feedback_parts.append("Calculated values appear plausible.")
    else:
        feedback_parts.append(f"Values implausible or constant (distinct: {distinct}, plausible: {plausible}).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }