#!/usr/bin/env python3
"""
Verifier for academic_performance_pivot task.

Criteria:
1. File saved (10 pts)
2. Pivot transformation (Columns Math/Science exist) (35 pts)
3. Visual Type (Scatter Chart) (15 pts)
4. Visual Configuration (Axes use Math/Science) (25 pts)
5. Analytics (Trend Line) (15 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_academic_performance_pivot(traj, env_info, task_info):
    """
    Verify that the agent pivoted the data and created a scatter chart with a trend line.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env("C:/Users/Docker/Desktop/task_result.json", temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to copy result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    
    # 1. File Saved (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but timestamp check failed.")
    else:
        feedback_parts.append("File not found.")
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Pivot Transformation (35 pts)
    # We check if columns "Math" and "Science" were detected in the layout properties.
    if result.get('pivot_columns_detected'):
        score += 35
        feedback_parts.append("Data pivoted successfully (Math/Science columns found).")
    else:
        feedback_parts.append("Pivot transformation not detected - columns 'Math'/'Science' not found in model.")

    # 3. Visual Type (15 pts)
    if result.get('scatter_chart_found'):
        score += 15
        feedback_parts.append("Scatter chart found.")
    else:
        feedback_parts.append("Scatter chart not found.")

    # 4. Visual Configuration (25 pts)
    # Did they put Math/Science on the axes?
    axes_correct = result.get('math_axis_found') and result.get('science_axis_found')
    if axes_correct:
        score += 25
        feedback_parts.append("Axes configured correctly.")
    elif result.get('math_axis_found') or result.get('science_axis_found'):
        score += 10
        feedback_parts.append("One axis configured correctly.")
    else:
        feedback_parts.append("Axes incorrect or not using pivoted columns.")

    # 5. Trend Line (15 pts)
    if result.get('trend_line_found'):
        score += 15
        feedback_parts.append("Trend line added.")
    else:
        feedback_parts.append("Trend line not found in scatter chart.")

    # Final Score
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }