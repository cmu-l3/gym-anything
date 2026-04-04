#!/usr/bin/env python3
"""
Verifier for nyc_real_estate_market task.

Scoring (100 points total):
1. File Saved (10 pts)
2. Calculated Column 'Price_Per_SqFt' (15 pts)
3. Measure 'Median_PPSF' (20 pts)
4. Visuals: Bar Chart & Line Chart (10 pts)
5. Top 10 Filter Configuration (25 pts)
6. Page Level Filters (Price/SqFt) (20 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nyc_real_estate(traj, env_info, task_info):
    """
    Verify the NYC Real Estate Market Analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Saved (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("✅ File saved")
    elif result.get('file_exists'):
        score += 5
        feedback_parts.append("⚠️ File exists but timestamp check unclear")
    else:
        feedback_parts.append("❌ File not found")
        # Critical failure
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Calculated Column (15 pts)
    if result.get('model_has_column'):
        score += 15
        feedback_parts.append("✅ 'Price_Per_SqFt' column found")
    else:
        feedback_parts.append("❌ 'Price_Per_SqFt' column missing")

    # 3. Median Measure (20 pts)
    if result.get('model_has_measure'):
        score += 20
        feedback_parts.append("✅ 'Median_PPSF' measure found")
    else:
        feedback_parts.append("❌ 'Median_PPSF' measure missing")

    # 4. Visuals (10 pts)
    visuals = result.get('visual_types', [])
    if 'clusteredBarChart' in visuals and 'lineChart' in visuals:
        score += 10
        feedback_parts.append("✅ Visuals present")
    elif 'clusteredBarChart' in visuals or 'lineChart' in visuals:
        score += 5
        feedback_parts.append("⚠️ Some visuals missing")
    else:
        feedback_parts.append("❌ Required visuals not found")

    # 5. Top 10 Filter (25 pts)
    if result.get('layout_has_top_n'):
        score += 25
        feedback_parts.append("✅ Top 10 filter applied")
    else:
        feedback_parts.append("❌ Top N filter missing/incorrect")

    # 6. Page Filters (20 pts)
    if result.get('layout_has_page_filter'):
        score += 20
        feedback_parts.append("✅ Page filters (clean data) applied")
    else:
        feedback_parts.append("❌ Page filters missing")

    # Final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }