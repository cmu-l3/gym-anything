#!/usr/bin/env python3
"""
Verifier for sales_histogram_binning task.

Scoring (100 points total):
- File saved (15 pts): Sales_Distribution.pbix exists and modified during task
- Page name (10 pts): Page named "Distribution Analysis"
- Binning used (20 pts): Evidence of binning groups in DataModel
- Histogram visual (15 pts): clusteredColumnChart present
- KPI Card visual (15 pts): multiRowCard present
- Measures (25 pts): Median_Sales and Stdev_Sales present in DataModel

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_sales_histogram_binning(traj, env_info, task_info):
    """Verify the Power BI sales histogram task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from Windows VM
    # Note: Path is Windows path inside VM, verified via copy_from_env handling
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/histogram_result.json", temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification results from VM"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Saved & Timestamp (15 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 15
        feedback_parts.append("File saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but timestamp check failed (possibly pre-existing).")
    else:
        feedback_parts.append("Sales_Distribution.pbix not found.")

    # 2. Page Name (10 pts)
    if result.get('page_name_correct'):
        score += 10
        feedback_parts.append("Page renamed to 'Distribution Analysis'.")
    else:
        feedback_parts.append("Page name incorrect or default.")

    # 3. Binning (20 pts)
    if result.get('binning_found'):
        score += 20
        feedback_parts.append("Binning/Grouping detected in DataModel.")
    else:
        feedback_parts.append("No Binning/Grouping detected.")

    # 4. Visuals (30 pts total)
    visuals = result.get('visuals_found', [])
    if "clusteredColumnChart" in visuals:
        score += 15
        feedback_parts.append("Histogram (Column Chart) found.")
    else:
        feedback_parts.append("Histogram missing.")
        
    if "multiRowCard" in visuals:
        score += 15
        feedback_parts.append("Multi-row Card found.")
    else:
        feedback_parts.append("Multi-row Card missing.")

    # 5. Measures (25 pts)
    measures = result.get('measures_found', [])
    if "Median_Sales" in measures:
        score += 12.5
        feedback_parts.append("Median_Sales measure found.")
    else:
        feedback_parts.append("Median_Sales measure missing.")
        
    if "Stdev_Sales" in measures:
        score += 12.5
        feedback_parts.append("Stdev_Sales measure found.")
    else:
        feedback_parts.append("Stdev_Sales measure missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }