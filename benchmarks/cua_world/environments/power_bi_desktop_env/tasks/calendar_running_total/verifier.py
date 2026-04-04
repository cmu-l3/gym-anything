#!/usr/bin/env python3
"""
Verifier for calendar_running_total task.

Scoring (100 points total):
1. File saved (10 pts): Cumulative_Revenue_Report.pbix exists and is new
2. DateTable exists (20 pts): 'DateTable' found in model
3. DateTable columns (10 pts): 'Year' and 'MonthNum' found in model
4. Cumulative_Revenue measure (25 pts): 'Cumulative_Revenue' found in model
5. Area chart visual (20 pts): 'areaChart' visual type present
6. Card visual (15 pts): 'card' visual type present

Pass threshold: 65 points (Must have file + measure + area chart at minimum)
"""

import json
import os
import tempfile
import logging
import time

logger = logging.getLogger(__name__)

def verify_calendar_running_total(traj, env_info, task_info):
    """
    Verify the cumulative revenue report task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Retrieve result JSON from the Windows VM
    # The export script saves it to C:\Users\Docker\Desktop\cumulative_revenue_result.json
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/cumulative_revenue_result.json", temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve verification results: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to parse verification results"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Calculate Score
    score = 0
    feedback_parts = []
    
    # 1. File saved (10 pts)
    file_exists = result.get('file_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if file_exists and created_during:
        score += 10
        feedback_parts.append("✅ File saved correctly")
    elif file_exists:
        # Penalize if it seems like it wasn't created in this session (anti-gaming)
        score += 0
        feedback_parts.append("❌ File exists but timestamp predates task start")
    else:
        feedback_parts.append("❌ File not found")
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # 2. DateTable exists (20 pts)
    found_tables = result.get('found_tables', [])
    if "DateTable" in found_tables:
        score += 20
        feedback_parts.append("✅ DateTable found")
    else:
        feedback_parts.append("❌ DateTable not found in model")

    # 3. DateTable columns (10 pts)
    found_columns = result.get('found_columns', [])
    has_year = "Year" in found_columns
    has_month = "MonthNum" in found_columns
    
    if has_year and has_month:
        score += 10
        feedback_parts.append("✅ Date columns found")
    elif has_year or has_month:
        score += 5
        feedback_parts.append("⚠️ Partial date columns found")
    else:
        feedback_parts.append("❌ Date columns (Year/MonthNum) not found")

    # 4. Cumulative_Revenue measure (25 pts)
    found_measures = result.get('found_measures', [])
    if "Cumulative_Revenue" in found_measures:
        score += 25
        feedback_parts.append("✅ Cumulative_Revenue measure found")
    else:
        feedback_parts.append("❌ Cumulative_Revenue measure not found")

    # 5. Area Chart (20 pts)
    visual_types = result.get('visual_types', [])
    # PBI visual types: 'areaChart'
    has_area = "areaChart" in visual_types
    if has_area:
        score += 20
        feedback_parts.append("✅ Area Chart present")
    else:
        feedback_parts.append(f"❌ Area Chart missing (Found: {visual_types})")

    # 6. Card Visual (15 pts)
    has_card = "card" in visual_types
    if has_card:
        score += 15
        feedback_parts.append("✅ Card Visual present")
    else:
        feedback_parts.append("❌ Card Visual missing")

    # Final Evaluation
    passed = score >= 65
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }