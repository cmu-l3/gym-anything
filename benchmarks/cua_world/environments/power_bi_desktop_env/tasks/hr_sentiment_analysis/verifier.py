#!/usr/bin/env python3
"""
Verifier for HR Employee Sentiment Analysis task.

Scoring (100 points total):
- File saved (10 pts): HR_Sentiment_Analysis.pbix exists.
- Data Unpivoted (40 pts): Detected via usage of "Question"/"Attribute" field on Axis.
- Correct Visual (20 pts): hundredPercentStackedBarChart present.
- Axes Configured (15 pts): Question on Axis, Response on Legend.
- Sort Order/Data Model (15 pts): Valid Response field used in legend (implies valid model structure).

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hr_sentiment_analysis(traj, env_info, task_info):
    """Verify that survey data was unpivoted and visualized correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/hr_result.json", temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to copy result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Saved (10 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 10
        feedback_parts.append("File saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("File exists but timestamp verification failed.")
    else:
        feedback_parts.append("HR_Sentiment_Analysis.pbix not found.")
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # 2. Visual Type (20 pts)
    visuals = result.get('visual_types', [])
    if "hundredPercentStackedBarChart" in visuals:
        score += 20
        feedback_parts.append("Correct 100% Stacked Bar Chart found.")
    else:
        feedback_parts.append(f"Expected 100% Stacked Bar Chart, found: {visuals}")

    # 3. Unpivot Check (40 pts)
    # The export script heuristically checks if the Axis field contains "Question" or "Attribute"
    # This implies the user successfully unpivoted the 5 Q columns into one.
    if result.get('unpivot_detected'):
        score += 40
        feedback_parts.append("Data unpivoted correctly (Question column on Axis).")
    else:
        feedback_parts.append("Unpivot not detected. Ensure you unpivoted the question columns.")

    # 4. Axes & Legend Configuration (15 pts)
    # Checked if the correct visual had fields mapped to Category and Series
    axis_fields = result.get('axis_fields', [])
    legend_fields = result.get('legend_fields', [])
    
    if axis_fields and legend_fields:
        score += 15
        feedback_parts.append("Visual axes configured correctly.")
    else:
        feedback_parts.append("Visual is missing required Axis or Legend fields.")

    # 5. Sort/Model Structure (15 pts)
    # If 'Response' or 'Value' is in the legend, and unpivot is true, they likely did the modeling.
    # We give points if the legend field looks correct (Response/Value), implying they didn't just drag Q1 into values.
    if result.get('sort_model_detected'):
        score += 15
        feedback_parts.append("Legend field configured correctly (Response).")
    else:
        feedback_parts.append("Legend field 'Response' not detected.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }